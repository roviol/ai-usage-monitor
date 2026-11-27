import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_usage_monitor/domain/model.dart';
import 'package:ai_usage_monitor/ui/tray.dart';
import 'package:menu_base/menu_base.dart'; // tray_manager re-export

ProviderSnapshot snapshotOf(Health health, {String id = 'a', String name = 'A'}) => ProviderSnapshot(
      providerId: id,
      displayName: name,
      observedAt: DateTime.fromMillisecondsSinceEpoch(1785942000000, isUtc: true),
      freshness: Freshness.fresh,
      health: health,
    );

void main() {
  group('tray icon health mapping', () {
    test('aggregate icon health follows aggregateHealth', () {
      final presenter = TrayPresenter();
      expect(
        presenter.aggregateIconHealth([snapshotOf(Health.healthy), snapshotOf(Health.healthy)]),
        Health.healthy,
      );
      expect(
        presenter.aggregateIconHealth([snapshotOf(Health.healthy), snapshotOf(Health.disabled)]),
        Health.healthy,
      );
      expect(
        presenter.aggregateIconHealth([snapshotOf(Health.healthy), snapshotOf(Health.partial)]),
        Health.partial,
      );
      expect(
        presenter.aggregateIconHealth([snapshotOf(Health.healthy), snapshotOf(Health.error)]),
        Health.error,
      );
      expect(presenter.aggregateIconHealth([]), Health.disabled);
    });

    test('aggregate label matches the tooltip prefix', () {
      expect(trayAggregateLabel(Health.healthy), 'IA: healthy');
      expect(trayAggregateLabel(Health.partial), 'IA: partial');
      expect(trayAggregateLabel(Health.error), 'IA: error');
      expect(trayAggregateLabel(Health.disabled), 'IA: disabled');
    });

    test('tray icon color maps per health', () {
      expect(
        trayIconColor(Health.healthy, Brightness.dark),
        isNot(trayIconColor(Health.error, Brightness.dark)),
      );
      expect(trayIconColor(Health.disabled, Brightness.light), trayIconColor(Health.disabled, Brightness.dark));
    });
  });

  group('tooltip ordering and truncation', () {
    test('errors come first and disabled providers are skipped', () {
      final presenter = TrayPresenter();
      final snapshots = [
        snapshotOf(Health.disabled, id: 'x', name: 'X'),
        snapshotOf(Health.healthy, id: 'b', name: 'B'),
        snapshotOf(Health.error, id: 'c', name: 'C'),
        snapshotOf(Health.partial, id: 'a', name: 'A'),
      ];
      final tooltip = presenter.tooltip(snapshots, DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
      expect(tooltip, startsWith('IA: error'));
      expect(tooltip, contains('C:'));
      expect(tooltip, contains('A:'));
      expect(tooltip, contains('B:'));
      expect(tooltip, isNot(contains('X:')));
    });

    test('tooltip truncates at the cap keeping the header', () {
      const presenter = TrayPresenter(maxCharacters: 40);
      final tooltip = presenter.tooltip(
        [snapshotOf(Health.healthy, id: 'long-name', name: 'Very long provider name here')],
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
      expect(tooltip.length, lessThanOrEqualTo(40));
    });

    test('stale suffix appears', () {
      final presenter = TrayPresenter();
      final snapshot = snapshotOf(Health.healthy, id: 'b', name: 'B')..freshness = Freshness.stale;
      final tooltip = presenter.tooltip([snapshot], DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
      expect(tooltip, contains('stale'));
    });

    test('empty list keeps the aggregate header like the reference', () {
      const presenter = TrayPresenter();
      // An empty provider list aggregates to disabled and the tooltip keeps
      // the 'IA: …' header; the fallback name appears only when truncation
      // leaves nothing.
      expect(
        presenter.tooltip([], DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)),
        'IA: disabled',
      );
    });
  });

  group('menu enablement', () {
    test('overlay items enabled only when the overlay is enabled', () {
      final disabled = buildTrayMenu(
        overlay: const TrayOverlayState(enabled: false, visible: true, locked: true),
        windowsPlatform: true,
      );
      final visibleItem = (disabled.items ?? const <MenuItem>[]).whereType<MenuItem>().where((item) => item.key == TrayMenuKeys.overlayVisible).single;
      expect(visibleItem.disabled, isTrue);
      final lockItem = (disabled.items ?? const <MenuItem>[]).whereType<MenuItem>().where((item) => item.key == TrayMenuKeys.overlayLock).single;
      expect(lockItem.disabled, isTrue);

      final enabled = buildTrayMenu(
        overlay: const TrayOverlayState(enabled: true, visible: false, locked: false),
        windowsPlatform: true,
      );
      final showItem = (enabled.items ?? const <MenuItem>[]).whereType<MenuItem>().where((item) => item.key == TrayMenuKeys.overlayVisible).single;
      expect(showItem.disabled, isFalse);
      expect(showItem.label, 'Mostrar overlay');
    });

    test('lock item is Windows-only', () {
      final linux = buildTrayMenu(
        overlay: const TrayOverlayState(enabled: true, visible: true, locked: true),
        windowsPlatform: false,
      );
      expect((linux.items ?? const <MenuItem>[]).whereType<MenuItem>().where((item) => item.key == TrayMenuKeys.overlayLock), isEmpty);

      final windows = buildTrayMenu(
        overlay: const TrayOverlayState(enabled: true, visible: true, locked: false),
        windowsPlatform: true,
      );
      final lockItem = (windows.items ?? const <MenuItem>[]).whereType<MenuItem>().where((item) => item.key == TrayMenuKeys.overlayLock).single;
      expect(lockItem.disabled, isFalse);
      expect(lockItem.label, 'Bloquear overlay');
    });

    test('core actions are always enabled', () {
      final menu = buildTrayMenu(
        overlay: const TrayOverlayState(enabled: false, visible: true, locked: true),
        windowsPlatform: false,
      );
      final labels = (menu.items ?? const <MenuItem>[]).whereType<MenuItem>().map((item) => item.label).toList();
      expect(labels, contains('Abrir panel'));
      expect(labels, contains('Actualizar todos'));
      expect(labels, contains('Configuración…'));
      expect(labels, contains('Salir'));
    });
  });

  group('left-click activation', () {
    test('left click opens the dashboard', () {
      const presenter = TrayPresenter();
      expect(presenter.opensDashboardOnLeftClick, isTrue);
    });
  });
}