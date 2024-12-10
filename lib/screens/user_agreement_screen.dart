// ignore_for_file: unused_catch_stack

import 'package:flutter/material.dart';
import 'package:karing/app/modules/remote_config_manager.dart';
import 'package:karing/app/utils/app_utils.dart';
import 'package:karing/app/utils/assets_utils.dart';
import 'package:karing/app/utils/platform_utils.dart';
import 'package:karing/i18n/strings.g.dart';
import 'package:karing/screens/dialog_utils.dart';
import 'package:karing/screens/theme_config.dart';
import 'package:karing/screens/webview_helper.dart';
import 'package:karing/screens/widgets/framework.dart';

class UserAgreementScreen extends LasyRenderingStatefulWidget {
  static RouteSettings routSettings() {
    return const RouteSettings(name: "UserAgreementScreen");
  }

  const UserAgreementScreen({super.key});

  @override
  State<UserAgreementScreen> createState() => _UserAgreementScreenState();
}

class _UserAgreementScreenState
    extends LasyRenderingState<UserAgreementScreen> {
  String _res = "";

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final tcontext = Translations.of(context);
    Size windowSize = MediaQuery.of(context).size;
    String termOfUse = AppUtils.getTermsOfServiceUrl();
    return PopScope(
        canPop: false,
        child: Scaffold(
          appBar: PreferredSize(
            preferredSize: Size.zero,
            child: AppBar(),
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 0),
              child: Column(
                children: [
                  const SizedBox(
                    height: 20,
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(tcontext.UserAgreementScreen.privacyFirst,
                            style: const TextStyle(
                              fontSize: ThemeConfig.kFontSizeListItem,
                              fontWeight: ThemeConfig.kFontWeightListItem,
                            )),
                        const SizedBox(
                          height: 20,
                        ),
                        Container(
                          alignment: Alignment.topCenter,
                          height: windowSize.height * 0.68,
                          child: FutureBuilder(
                            future: getData(),
                            builder: (BuildContext context,
                                AsyncSnapshot<String> snapshot) {
                              String data =
                                  snapshot.hasData ? snapshot.data! : "";
                              return Text.rich(
                                TextSpan(
                                  text: data,
                                ),
                              );
                            },
                          ),
                        ),
                        SizedBox(
                          height: 45.0,
                          child: ElevatedButton(
                            autofocus: PlatformUtils.maybeTV(),
                            child: Text(
                                tcontext.UserAgreementScreen.agreeAndContinue),
                            onPressed: () {
                              Navigator.pop(context);
                            },
                          ),
                        ),
                        const SizedBox(
                          height: 20,
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            termOfUse.isNotEmpty
                                ? InkWell(
                                    child: Text(
                                      tcontext.termOfUse,
                                      style: const TextStyle(
                                          color: Colors.blueAccent),
                                    ),
                                    onTap: () async {
                                      await WebviewHelper.loadUrl(context,
                                          AppUtils.getTermsOfServiceUrl(),
                                          title: tcontext.termOfUse,
                                          useInappWebViewForPC: true);
                                    })
                                : const SizedBox(
                                    width: 0,
                                  ),
                            termOfUse.isNotEmpty
                                ? const SizedBox(
                                    width: 60,
                                  )
                                : const SizedBox(
                                    width: 0,
                                  ),
                            InkWell(
                                child: Text(
                                  tcontext.privacyPolicy,
                                  style:
                                      const TextStyle(color: Colors.blueAccent),
                                ),
                                onTap: () async {
                                  var remoteConfig =
                                      RemoteConfigManager.getConfig();
                                  bool ok = await WebviewHelper.loadUrl(
                                      context, remoteConfig.privacyPolicy,
                                      title: tcontext.privacyPolicy,
                                      useInappWebViewForPC: true);

                                  if (!ok) {
                                    if (!context.mounted) {
                                      return;
                                    }
                                    DialogUtils.showPrivacyPolicy(context);
                                  }
                                }),
                          ],
                        )
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ));
  }

  Future<String> getData() async {
    if (_res.isNotEmpty) {
      return _res;
    }

    _res = await AssetsUtils.loadUserAgreement();
    return _res;
  }
}
