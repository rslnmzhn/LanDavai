#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif
#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#endif
#ifdef HAVE_APPINDICATOR
#ifdef USE_AYATANA_APPINDICATOR
#include <libayatana-appindicator/app-indicator.h>
#else
#include <libappindicator/app-indicator.h>
#endif
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  FlMethodChannel* method_channel;
  gboolean minimize_to_tray_enabled;
  gboolean exit_requested;
  gboolean tray_support_logged;
#ifdef HAVE_APPINDICATOR
  AppIndicator* tray_indicator;
  GtkWidget* tray_menu;
#endif
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static gboolean my_application_has_tray_support(MyApplication* self) {
#ifdef HAVE_APPINDICATOR
  return self->tray_indicator != nullptr;
#else
  (void)self;
  return FALSE;
#endif
}

static const gchar* my_application_detect_display_backend() {
  GdkDisplay* display = gdk_display_get_default();
  if (display == nullptr) {
    return "unknown";
  }
#ifdef GDK_WINDOWING_WAYLAND
  if (GDK_IS_WAYLAND_DISPLAY(display)) {
    return "wayland";
  }
#endif
#ifdef GDK_WINDOWING_X11
  if (GDK_IS_X11_DISPLAY(display)) {
    return "x11";
  }
#endif
  return "unknown";
}

static void my_application_log_tray_environment(MyApplication* self) {
  if (self->tray_support_logged) {
    return;
  }
  self->tray_support_logged = TRUE;

  const gchar* desktop = g_getenv("XDG_CURRENT_DESKTOP");
  const gchar* session = g_getenv("XDG_SESSION_TYPE");
  const gchar* backend = my_application_detect_display_backend();

  g_message(
      "Tray integration initialized. backend=%s session=%s desktop=%s", backend,
      session != nullptr ? session : "unknown",
      desktop != nullptr ? desktop : "unknown");
  if (desktop != nullptr && g_strrstr(desktop, "GNOME") != nullptr) {
    g_message(
        "GNOME tray visibility requires "
        "\"AppIndicator and KStatusNotifierItem Support\" extension.");
  }
}

static void my_application_show_window(MyApplication* self) {
  if (self->window == nullptr) {
    return;
  }
  gtk_widget_show(GTK_WIDGET(self->window));
  gtk_window_present(self->window);
}

#ifdef HAVE_APPINDICATOR
static void my_application_sync_tray_status(MyApplication* self) {
  if (self->tray_indicator == nullptr) {
    return;
  }
  app_indicator_set_status(
      self->tray_indicator,
      self->minimize_to_tray_enabled ? APP_INDICATOR_STATUS_ACTIVE
                                     : APP_INDICATOR_STATUS_PASSIVE);
}

static void my_application_on_open_from_tray(GtkMenuItem* item,
                                              gpointer user_data) {
  (void)item;
  MyApplication* self = MY_APPLICATION(user_data);
  my_application_show_window(self);
}

static void my_application_on_exit_from_tray(GtkMenuItem* item,
                                             gpointer user_data) {
  (void)item;
  MyApplication* self = MY_APPLICATION(user_data);
  self->exit_requested = TRUE;
  if (self->window != nullptr) {
    gtk_window_close(self->window);
    return;
  }
  g_application_quit(G_APPLICATION(self));
}

static gchar* my_application_resolve_tray_icon_path() {
  g_autofree gchar* executable_path = g_file_read_link("/proc/self/exe", nullptr);
  if (executable_path == nullptr) {
    return g_build_filename("data", "flutter_assets", "assets", "tray",
                            "landa_tray.png", nullptr);
  }

  g_autofree gchar* executable_dir = g_path_get_dirname(executable_path);
  return g_build_filename(executable_dir, "data", "flutter_assets", "assets",
                          "tray", "landa_tray.png", nullptr);
}
static void my_application_setup_tray(MyApplication* self) {
  if (self->tray_indicator != nullptr) {
    return;
  }

  g_autofree gchar* tray_icon_path = my_application_resolve_tray_icon_path();
  const gchar* tray_icon = "network-workgroup";
  if (tray_icon_path != nullptr &&
      g_file_test(tray_icon_path, G_FILE_TEST_EXISTS)) {
    tray_icon = tray_icon_path;
  } else {
    g_warning("Landa tray icon not found. fallback=network-workgroup");
  }

  // AppIndicator is deprecated upstream but still required for tray support.
  // Silence the deprecation warning to keep -Werror builds passing.
  G_GNUC_BEGIN_IGNORE_DEPRECATIONS
  self->tray_indicator = app_indicator_new(
      APPLICATION_ID, tray_icon,
      APP_INDICATOR_CATEGORY_APPLICATION_STATUS);
  G_GNUC_END_IGNORE_DEPRECATIONS
  if (self->tray_indicator == nullptr) {
    g_warning("Failed to create AppIndicator tray instance.");
    return;
  }

  self->tray_menu = gtk_menu_new();
  GtkWidget* open_item = gtk_menu_item_new_with_label("Open Landa");
  GtkWidget* exit_item = gtk_menu_item_new_with_label("Exit");

  g_signal_connect(open_item, "activate", G_CALLBACK(my_application_on_open_from_tray),
                   self);
  g_signal_connect(exit_item, "activate", G_CALLBACK(my_application_on_exit_from_tray),
                   self);

  gtk_menu_shell_append(GTK_MENU_SHELL(self->tray_menu), open_item);
  gtk_menu_shell_append(GTK_MENU_SHELL(self->tray_menu), exit_item);
  gtk_widget_show_all(self->tray_menu);

  app_indicator_set_menu(self->tray_indicator, GTK_MENU(self->tray_menu));
  app_indicator_set_icon_full(self->tray_indicator, tray_icon,
                              "Landa tray icon");
  my_application_sync_tray_status(self);
  my_application_log_tray_environment(self);
}
#endif

static void my_application_respond_success(FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_null()));
  g_autoptr(GError) error = nullptr;
  fl_method_call_respond(method_call, response, &error);
  if (error != nullptr) {
    g_warning("Failed to send method response: %s", error->message);
  }
}

static void my_application_respond_not_implemented(FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  g_autoptr(GError) error = nullptr;
  fl_method_call_respond(method_call, response, &error);
  if (error != nullptr) {
    g_warning("Failed to send method response: %s", error->message);
  }
}

static void my_application_method_call_handler(FlMethodChannel* channel,
                                               FlMethodCall* method_call,
                                               gpointer user_data) {
  (void)channel;
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);

  if (g_strcmp0(method, "setMinimizeToTrayEnabled") == 0) {
    gboolean enabled = TRUE;
    FlValue* args = fl_method_call_get_args(method_call);
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* value = fl_value_lookup_string(args, "enabled");
      if (value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_BOOL) {
        enabled = fl_value_get_bool(value);
      }
    }

    self->minimize_to_tray_enabled = enabled;
#ifdef HAVE_APPINDICATOR
    my_application_setup_tray(self);
    my_application_sync_tray_status(self);
#else
    if (enabled && !self->tray_support_logged) {
      self->tray_support_logged = TRUE;
      g_warning("Tray support is disabled. Install appindicator support.");
    }
#endif
    if (!enabled && self->window != nullptr &&
        !gtk_widget_get_visible(GTK_WIDGET(self->window))) {
      my_application_show_window(self);
    }
    my_application_respond_success(method_call);
    return;
  }

  my_application_respond_not_implemented(method_call);
}

static void my_application_setup_method_channel(MyApplication* self,
                                                FlView* view) {
  FlEngine* engine = fl_view_get_engine(view);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
  FlMethodCodec* codec = FL_METHOD_CODEC(fl_standard_method_codec_new());
  self->method_channel =
      fl_method_channel_new(messenger, "landa/network", codec);
  g_object_unref(codec);

  fl_method_channel_set_method_call_handler(
      self->method_channel, my_application_method_call_handler, self, nullptr);
}

static void my_application_on_window_destroy(GtkWidget* widget,
                                             gpointer user_data) {
  (void)widget;
  MyApplication* self = MY_APPLICATION(user_data);
  self->window = nullptr;
}

static gboolean my_application_on_window_delete_event(GtkWidget* widget,
                                                      GdkEvent* event,
                                                      gpointer user_data) {
  (void)event;
  MyApplication* self = MY_APPLICATION(user_data);
  if (self->exit_requested || !self->minimize_to_tray_enabled) {
    return FALSE;
  }
  if (!my_application_has_tray_support(self)) {
    return FALSE;
  }

  gtk_widget_hide(widget);
  return TRUE;
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  if (self->window != nullptr) {
    my_application_show_window(self);
    return;
  }

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->window = window;

  g_signal_connect(window, "destroy", G_CALLBACK(my_application_on_window_destroy),
                   self);
  g_signal_connect(window, "delete-event",
                   G_CALLBACK(my_application_on_window_delete_event), self);

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Landa");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Landa");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  my_application_setup_method_channel(self, view);
#ifdef HAVE_APPINDICATOR
  my_application_setup_tray(self);
#endif

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
#ifdef HAVE_APPINDICATOR
  MyApplication* self = MY_APPLICATION(application);
  if (self->tray_indicator != nullptr) {
    app_indicator_set_status(self->tray_indicator, APP_INDICATOR_STATUS_PASSIVE);
  }
#endif

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_object(&self->method_channel);
#ifdef HAVE_APPINDICATOR
  g_clear_object(&self->tray_indicator);
  g_clear_pointer(&self->tray_menu, gtk_widget_destroy);
#endif
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->window = nullptr;
  self->method_channel = nullptr;
  self->minimize_to_tray_enabled = TRUE;
  self->exit_requested = FALSE;
  self->tray_support_logged = FALSE;
#ifdef HAVE_APPINDICATOR
  self->tray_indicator = nullptr;
  self->tray_menu = nullptr;
#endif
}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}

