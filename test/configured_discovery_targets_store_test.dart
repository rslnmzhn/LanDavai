import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/application/configured_discovery_targets_store.dart';
import 'package:landa/features/discovery/data/configured_discovery_targets_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late ConfiguredDiscoveryTargetsRepository repository;
  late ConfiguredDiscoveryTargetsStore store;

  setUp(() async {
    sqfliteFfiInit();
    database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE app_settings (
              setting_key TEXT PRIMARY KEY,
              setting_value TEXT NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
        },
      ),
    );
    repository = ConfiguredDiscoveryTargetsRepository.withDatabaseProvider(
      databaseProvider: () async => database,
    );
    store = ConfiguredDiscoveryTargetsStore(repository: repository);
  });

  tearDown(() async {
    store.dispose();
    await database.close();
  });

  test('loads empty targets by default', () async {
    await store.load();

    expect(store.targets, isEmpty);
  });

  test('normalizes, sorts, and persists configured targets', () async {
    await store.load();

    expect(await store.addTarget(' 100.64.0.8 '), isTrue);
    expect(await store.addTarget('192.168.1.15'), isTrue);
    expect(await store.addTarget('100.64.0.2'), isTrue);

    expect(store.targets, <String>['100.64.0.2', '100.64.0.8', '192.168.1.15']);

    final reloaded = ConfiguredDiscoveryTargetsStore(repository: repository);
    addTearDown(reloaded.dispose);
    await reloaded.load();

    expect(reloaded.targets, <String>[
      '100.64.0.2',
      '100.64.0.8',
      '192.168.1.15',
    ]);
  });

  test('rejects invalid and duplicate configured targets', () async {
    await store.load();

    expect(store.validationErrorFor(''), 'Введите IPv4-адрес.');
    expect(store.validationErrorFor('abc'), 'Введите корректный IPv4-адрес.');
    expect(
      store.validationErrorFor('127.0.0.1'),
      'Введите корректный IPv4-адрес.',
    );

    expect(await store.addTarget('100.64.0.8'), isTrue);
    expect(store.validationErrorFor('100.64.0.8'), 'Этот адрес уже добавлен.');
    expect(await store.addTarget('100.64.0.8'), isFalse);
  });

  test('removes configured targets', () async {
    await store.load();
    await store.addTarget('100.64.0.8');
    await store.addTarget('100.64.0.9');

    await store.removeTarget('100.64.0.8');

    expect(store.targets, <String>['100.64.0.9']);
  });
}
