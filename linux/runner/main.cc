#include "my_application.h"

int main(int argc, char** argv) {
  const gchar* session_type = g_getenv("XDG_SESSION_TYPE");
  const gchar* wayland_display = g_getenv("WAYLAND_DISPLAY");

  const gboolean prefer_wayland =
      (session_type != nullptr &&
       g_ascii_strcasecmp(session_type, "wayland") == 0) ||
      (wayland_display != nullptr && wayland_display[0] != '\0');

  if (prefer_wayland) {
    // Prefer Wayland in Wayland sessions, but keep X11 as fallback.
    g_setenv("GDK_BACKEND", "wayland,x11", TRUE);
    gdk_set_allowed_backends("wayland,x11");
  } else {
    gdk_set_allowed_backends("x11,wayland");
  }

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
