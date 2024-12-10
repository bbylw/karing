// ignore_for_file: empty_catches, unused_catch_stack

import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/rendering.dart';
import 'package:karing/app/private/ads_private.dart';
import 'package:karing/app/utils/did.dart';
import 'package:karing/screens/inapp_webview_screen.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inapp_notifications/flutter_inapp_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:karing/app/modules/app_lifecycle_state_notify_manager.dart';
import 'package:karing/app/modules/biz.dart';
import 'package:karing/app/modules/remote_config_manager.dart';
import 'package:karing/app/modules/remote_isp_config_manager.dart';
import 'package:karing/app/modules/setting_manager.dart';
import 'package:karing/app/private/sentry_utils_private.dart';
import 'package:karing/app/utils/analytics_utils.dart';
import 'package:karing/app/utils/app_args.dart';
import 'package:karing/app/utils/app_utils.dart';
import 'package:karing/app/utils/geoip_subnet_utils.dart';
import 'package:karing/app/utils/file_utils.dart';

import 'package:karing/app/utils/log.dart';
import 'package:karing/app/utils/path_utils.dart';
import 'package:karing/app/utils/platform_utils.dart';
import 'package:karing/app/utils/sentry_utils.dart';
import 'package:karing/app/utils/system_scheme_utils.dart';
import 'package:karing/app/utils/windows_version_helper.dart';
import 'package:karing/i18n/strings.g.dart';
import 'package:karing/screens/home_screen.dart';
//import 'package:karing/screens/splash_screen.dart';
import 'package:karing/screens/launch_failed_screen.dart';
import 'package:karing/screens/theme_data_dark.dart';
import 'package:karing/screens/themes.dart';
import 'package:karing/screens/widgets/routes.dart';
import 'package:move_to_background/move_to_background.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:vpn_service/vpn_service.dart';
import 'package:window_manager/window_manager.dart';
import 'package:windows_single_instance/windows_single_instance.dart';

List<String> processArgs = [];
StartFailedReason? startFailedReason;
String? startFailedReasonDesc;

void main(List<String> args) async {
  /* String dir = "E:\\dev\\KaringX\\karing-ruleset\\geo\\geoip";
  String target = path.join(dir, "geoip_subnets.json");
  var files = FileUtils.recursionFile(dir, filter: {".json"});
  var subnets = await GeoipSubnetUtils.genClientSubnet(files);
  await GeoipSubnetUtils.saveSubnets(subnets, target);
  return;*/

  processArgs = args;
  WidgetsFlutterBinding.ensureInitialized();
  await RemoteConfigManager.init();
  await SentryUtilsPrivate.init();
  await RemoteISPConfigManager.init();
  await LocaleSettings.useDeviceLocale();
  //runZonedGuarded(() async {// Zone mismatch
  if (PlatformDispatcher.instance.semanticsEnabled) {
    SemanticsBinding.instance.ensureSemantics();
  }
  await run(args);
  //}, (exception, stackTrace) async {
  //  await Sentry.captureException(exception, stackTrace: stackTrace);
  //});
}

Future<void> run(List<String> args) async {
  try {
    do {
      String profile = await PathUtils.profileDir();
      if (profile.isEmpty) {
        startFailedReason = StartFailedReason.invalidProfile;
        break;
      }
      String version = await AppUtils.getPackgetVersion();
      if (AppUtils.getBuildinVersion() != version) {
        startFailedReason = StartFailedReason.invalidVersion;
        break;
      }
      String exePath = Platform.resolvedExecutable.toUpperCase();
      if (PlatformUtils.isPC()) {
        if (path.basename(exePath).toLowerCase() !=
            PathUtils.getExeName().toLowerCase()) {
          startFailedReason = StartFailedReason.invalidProcess;
          break;
        }
      }
      if (Platform.isWindows) {
        var tmp = await getTemporaryDirectory();
        if (exePath.contains("UNC/") ||
            exePath.contains("UNC\\") ||
            exePath.startsWith(tmp.absolute.path.toUpperCase())) {
          startFailedReason = StartFailedReason.invalidInstallPath;
          break;
        }

        if (VersionHelper.instance.majorVersion != 0 &&
            VersionHelper.instance.majorVersion < 10) {
          startFailedReason = StartFailedReason.systemVersionLow;
          startFailedReasonDesc = "Windows >= 10.0";
          break;
        }
      } else if (Platform.isAndroid) {
        String version = await FlutterVpnService.getSystemVersion();
        int? v = int.tryParse(version);
        if (v != null && v < 26) {
          startFailedReason = StartFailedReason.systemVersionLow;
          startFailedReasonDesc = "Android >= 8.0";
          break;
        }
      }
    } while (false);
  } catch (err, stacktrace) {
    startFailedReason = StartFailedReason.exception;
    startFailedReasonDesc = err.toString();
  }

  if (PlatformUtils.isPC()) {
    await windowManager.ensureInitialized();
    const inProduction = bool.fromEnvironment("dart.vm.product");
    if (inProduction) {
      await windowManager.setResizable(false);
      await windowManager.setMaximizable(false);
    }

    await windowManager.center();
  }

  if (Platform.isWindows) {
    await WindowsSingleInstance.ensureSingleInstance(
        args, "karing_single_identifier", onSecondWindow: (args) async {
      if (await windowManager.isMinimized()) {
        await windowManager.restore();
      }
      await windowManager.focus();
    });
  }

  await SettingManager.init();
  if (PlatformUtils.isMobile()) {
    if (SettingManager.getConfig().ui.autoOrientation) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeRight
      ]);
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
  }
  bool first = await Did.getFirstTime();
  await InAppWebViewScreen.init();
  AdsPrivate.init(first);

  runApp(TranslationProvider(
    child: const MyApp(),
  ));
  if (Platform.isAndroid) {
    SystemUiOverlayStyle systemUiOverlayStyle = const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent);
    SystemChrome.setSystemUIOverlayStyle(systemUiOverlayStyle);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => MyAppState();
}

class MyAppState extends State<MyApp>
    with WidgetsBindingObserver, WindowListener, TrayListener {
  static const kMenuOpen = "show_window";
  static const kMenuExit = "exit_app";
  bool _launchAtStartup = false;
  bool _windowVisibleForMac = false;
  bool _trayGrey = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (PlatformUtils.isPC()) {
      windowManager.addListener(this);
      windowManager.setPreventClose(true);
      trayManager.addListener(this);
      _setTray(true, false, true);
    }
    AppLifecycleStateNofityManager.init();
    LocaleSettings.getLocaleStream().listen((event) {});
    String launchStartupArg = processArgs.firstWhere(
      (element) => element == AppArgs.launchStartup,
      orElse: () => '',
    );
    _launchAtStartup = launchStartupArg.isNotEmpty;
    AnalyticsUtils.logEvent(
        analyticsEventType: analyticsEventTypeApp,
        name: 'launch',
        parameters: {"value": _launchAtStartup},
        forceSubmit: true);

    AppLifecycleStateNofityManager.stateLaunch(_launchAtStartup);
    _init();
  }

  @override
  void dispose() async {
    AppLifecycleStateNofityManager.uninit();
    WidgetsBinding.instance.removeObserver(this);
    if (PlatformUtils.isPC()) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
      trayManager.destroy();
    }

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        Log.d("AppLifecycleState.resumed");
        AppLifecycleStateNofityManager.stateResumed("resumed");
        break;
      case AppLifecycleState.inactive:
        Log.d("AppLifecycleState.inactive");
        AppLifecycleStateNofityManager.stateInactive("inactive");
        break;
      case AppLifecycleState.detached:
        Log.d("AppLifecycleState.detached");
        break;
      case AppLifecycleState.paused:
        Log.d("AppLifecycleState.paused");
        AppLifecycleStateNofityManager.statePaused("paused");
        break;
      case AppLifecycleState.hidden:
        Log.d("AppLifecycleState.hidden");
        AppLifecycleStateNofityManager.stateInactive("hidden");
        break;
    }
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    if (Platform.isWindows) {
      windowManager.hide();
      return AppExitResponse.cancel;
    }
    _quit();
    return AppExitResponse.exit;
  }

  @override
  void didHaveMemoryPressure() {}

  @override
  Widget build(BuildContext context) {
    String schemeArg = processArgs.firstWhere(
      (element) {
        return element
                .trim()
                .startsWith(SystemSchemeUtils.getKaringSchemeWith()) ||
            element.trim().startsWith(SystemSchemeUtils.getClashSchemeWith());
      },
      orElse: () => '',
    );

    List<NavigatorObserver> observers = [];

    observers.add(AppRouteObserver.instance);
    observers.add(SentryUtils.getOvserver());

    return MultiProvider(
        providers: [ChangeNotifierProvider.value(value: Themes())],
        child: Consumer<Themes>(builder: (context, appTheme, _) {
          Provider.of<Themes>(context)
              .setTheme(SettingManager.getConfig().ui.theme, false);
          return Shortcuts(
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.select): ActivateIntent()
              },
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                locale: TranslationProvider.of(context).flutterLocale,
                supportedLocales: AppLocaleUtils.supportedLocales,
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                navigatorObservers: observers,
                home: PopScope(
                    canPop: false,
                    onPopInvokedWithResult: (didPop, result) {
                      if (Platform.isAndroid || Platform.isIOS) {
                        MoveToBackground.moveTaskToBack();
                      }
                    },
                    child: startFailedReason != null
                        ? LaunchFailedScreen(
                            startFailedReason: startFailedReason!,
                            startFailedReasonDesc: startFailedReasonDesc,
                          )
                        : HomeScreen(launchUrl: schemeArg.trim())),
                builder: InAppNotifications.init(
                    builder: SettingManager.getConfig().ui.disableFontScaler
                        ? (context, widget) {
                            return MediaQuery(
                              data: MediaQuery.of(context)
                                  .copyWith(textScaler: TextScaler.noScaling),
                              child: widget!,
                            );
                          }
                        : null),
                themeMode: appTheme.themeMode(),
                theme: appTheme.themeData(context),
                darkTheme: ThemeDataDark.theme(context),
              ));
        }));
  }

  @override
  void onWindowClose() {
    Log.d("onWindowClose");
    windowManager.hide();
    _windowVisibleForMac = false;
    AppLifecycleStateNofityManager.statePaused("close");
  }

  @override
  void onWindowMinimize() {
    _windowVisibleForMac = false;
    Log.d("onWindowMinimize");
    AppLifecycleStateNofityManager.statePaused("minimize");
  }

  @override
  void onWindowRestore() {
    _windowVisibleForMac = true;
    Log.d("onWindowRestore");
    AppLifecycleStateNofityManager.stateResumed("restore");
  }

  @override
  void onWindowFocus() {
    if (Platform.isMacOS) {
      if (!_windowVisibleForMac) {
        Log.d("onWindowFocus");
        _windowVisibleForMac = true;
        AppLifecycleStateNofityManager.stateResumed("restore");
      }
    }
  }

  @override
  void onWindowTaskbarCreated() {
    _setTray(_trayGrey, true, true);
  }

  @override
  void onWindowDeviceShutdown() {
    Log.d("main.dart onWindowDeviceShutdown");
    _quit();
  }

  @override
  void onWindowUserSessionDisconnect() {
    Log.d("main.dart onWindowUserSessionDisconnect");
    if (SettingManager.getConfig().quitWhenSwitchSystemUser) {
      _quit();
    }
  }

  void firstShowWindow(bool forceShow) {
    if (PlatformUtils.isPC()) {
      windowManager.waitUntilReadyToShow(null, () async {
        if (forceShow ||
            (Platform.isWindows &&
                !SettingManager.getConfig().ui.hideAfterLaunch)) {
          await windowManager.show();
          onWindowRestore();
        }
      });
    }
  }

  Future<void> _init() async {
    Biz.onQuit(() {
      _quit();
    });

    Biz.onVPNStateChanged((bool connected) {
      if (PlatformUtils.isPC()) {
        if (_trayGrey == !connected) {
          return;
        }
        _setTray(!connected, false, false);
      }
    });
    if (startFailedReason == null) {
      Log.w(
          'launch ${Platform.resolvedExecutable}, $processArgs, ${Directory.current.absolute.path}');

      Biz.onInitHomeFinish(() {
        firstShowWindow(false);
      });

      await Biz.init(_launchAtStartup);
    } else {
      firstShowWindow(true);
    }
  }

  Future<void> _uninit() async {
    if (startFailedReason == null) {
      await Biz.uninit();
    }
    if (PlatformUtils.isPC()) {
      await trayManager.destroy();
    }
  }

  Future<void> _quit() async {
    await _uninit();
    await ServicesBinding.instance.exitApplication(AppExitType.required);
  }

  void _setTray(bool grey, bool destroy, bool quitIfFailed) {
    Future.delayed(const Duration(milliseconds: 300), () async {
      if (destroy) {
        await trayManager.destroy();
      }

      try {
        if (Platform.isWindows) {
          await trayManager.setIcon(
            grey ? 'assets/icons/grey_tray.ico' : 'assets/icons/tray.ico',
          );
        } else {
          await trayManager.setIcon(
            grey ? 'assets/icons/grey_tray.png' : 'assets/icons/tray.png',
          );
        }
        _trayGrey = grey;
      } catch (err, stacktrace) {
        Log.w("setIcon failed: ${err.toString()}");
        if (quitIfFailed) {
          Future.delayed(const Duration(milliseconds: 1000), () async {
            _quit();
          });
        }
      }
      if (!Platform.isLinux) {
        await trayManager.setToolTip(AppUtils.getName());
      }
    });
  }

  @override
  void onTrayIconMouseDown() async {
    if (await windowManager.isMinimized()) {
      await windowManager.restore();
    } else {
      await windowManager.show();
      onWindowRestore();
    }
  }

  @override
  void onTrayIconRightMouseDown() async {
    if (Platform.isWindows || Platform.isLinux /*|| Platform.isMacOS*/) {
      List<MenuItem> items = [
        MenuItem(
          key: kMenuOpen,
          label: t.main.tray.menuOpen,
        ),
        MenuItem(
          key: kMenuExit,
          label: t.main.tray.menuExit,
        ),
      ];
      await trayManager.setContextMenu(Menu(items: items));
      await trayManager.popUpContextMenu();
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    if (menuItem.key == kMenuExit) {
      await _quit();
    } else if (menuItem.key == kMenuOpen) {
      if (await windowManager.isMinimized()) {
        await windowManager.restore();
      } else {
        await windowManager.show();
        onWindowRestore();
      }
    }
  }
}
