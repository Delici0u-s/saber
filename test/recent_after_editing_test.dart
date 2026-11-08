import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/canvas/save_indicator.dart';
import 'package:saber/components/theming/dynamic_material_app.dart';
import 'package:saber/components/theming/saber_theme.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/routes.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';
import 'package:saber/pages/home/home.dart';

import 'utils/test_mock_channel_handlers.dart';

/// Opening a note from Recent and leaving it again keeps every note listed.
void main() {
  setUp(() async {
    FlavorConfig.setup();
    setupMockPathProvider();
    stows.sentryConsent.value = .granted;
    await FileManager.init();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          (_) async => null,
        );
  });

  for (final edit in const [false, true])
    for (final size in const [Size(1600, 1000), Size(400, 800)])
      testWidgets('notes stay listed after leaving one '
          '(${edit ? 'edited' : 'unchanged'}, $size)', (tester) async {
        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final names = ['recent a', 'recent b', 'recent c'];
        await tester.runAsync(() async {
          stows.recentFiles.value = [];
          for (final name in names.reversed) {
            final note = EditorCoreInfo(filePath: '/$name')
              ..pages.add(EditorPage());
            await note.saveToFile(currentPageIndex: null);
            note.dispose();
          }
        });

        await tester.pumpWidget(const _RecentApp());
        await tester.pumpAndSettle();
        for (final name in names) {
          expect(find.text(name), findsOneWidget, reason: '$name before');
        }

        await tester.tap(find.text('recent b'));
        for (var i = 0; i < 20; i++) {
          await tester.runAsync(
            () => Future.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(find.byType(Editor), findsOneWidget, reason: 'the note opened');
        if (edit) {
          final editor = tester.state<EditorState>(find.byType(Editor))
            ..insertPageAfter(0)
            ..saveToFile();
          // Leaving waits for the save, like the back button does.
          for (var i = 0; i < 40 && editor.savingState.value != .saved; i++) {
            await tester.runAsync(
              () => Future.delayed(const Duration(milliseconds: 50)),
            );
            await tester.pump(const Duration(milliseconds: 50));
          }
          expect(editor.savingState.value, SavingState.saved);
        }

        // Leave the note like the back button does.
        await tester
            .state<NavigatorState>(find.byType(Navigator).first)
            .maybePop();
        for (var i = 0; i < 20; i++) {
          await tester.runAsync(
            () => Future.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump(const Duration(milliseconds: 50));
        }

        expect(find.byType(Editor), findsNothing, reason: 'the note closed');
        for (final name in names) {
          expect(find.text(name), findsOneWidget, reason: '$name after');
        }
      });
}

class _RecentApp extends StatelessWidget {
  const new();
  @override
  Widget build(BuildContext context) {
    final theme = SaberTheme.createThemeFromSeed(
      Colors.yellow,
      .light,
      .android,
    );
    final router = GoRouter(
      initialLocation: '${RoutePaths.prefixOfHome}/${HomePage.recentSubpage}',
      routes: [
        GoRoute(
          path: RoutePaths.home,
          builder: (context, state) => HomePage(
            subpage: state.pathParameters['subpage'] ?? HomePage.recentSubpage,
            path: state.uri.queryParameters['path'],
          ),
        ),
      ],
    );
    return TranslationProvider(
      child: ExplicitlyThemedApp(
        title: 'Saber',
        router: router,
        themeMode: ThemeMode.light,
        theme: theme,
        darkTheme: theme,
      ),
    );
  }
}
