import 'package:flutter/material.dart';
import 'package:karing/app/runtime/return_result.dart';
import 'package:karing/app/utils/app_scheme_actions.dart';
import 'package:karing/app/utils/backup_and_sync_utils.dart';
import 'package:karing/app/utils/file_utils.dart';
import 'package:karing/app/utils/http_utils.dart';
import 'package:karing/app/utils/path_utils.dart';
import 'package:karing/app/utils/platform_utils.dart';
import 'package:karing/app/utils/system_scheme_utils.dart';
import 'package:karing/app/utils/url_launcher_utils.dart';
import 'package:karing/i18n/strings.g.dart';
import 'package:karing/screens/add_profile_by_link_or_content_screen.dart';
import 'package:karing/screens/dialog_utils.dart';
import 'package:karing/screens/group_helper.dart';
import 'package:path/path.dart' as path;

class SchemeHandler {
  static void Function()? vpnConnect;
  static void Function()? vpnDisconnect;
  static void Function()? vpnReconnect;
  static Future<ReturnResultError?> handle(
      BuildContext context, String url) async {
    //clash://install-config?url=trojan://41bec492-cd79-4b57-9a15-7d2bb00fcfca@163.123.192.57:443?allowInsecure=1#%F0%9F%87%BA%F0%9F%87%B8%20_US_%E7%BE%8E%E5%9B%BD|trojan://a8f54f4e-1d9d-44e4-9ef7-50ee7ba89561@jk.jkk.kisskiss.pro:1887?allowInsecure=1#%F0%9F%87%B0%F0%9F%87%B7%20_KR_%E9%9F%A9%E5%9B%BD
    //clash://install-config?url=https://xxxxx.com/clash/config
    //stash://install-config?url=https%3A%2F%2Fwww.xxxxx.gay%2Fapi%2Fv1%2Fclient%2Fsubscribe%3Ftoken%3D&name=stars
    //sing-box://import-remote-profile?url=https://xxxxx:8443/proxy/fgram.json#mcivip%F0%9F%87%B9%F0%9F%87%B73%7CArefgram
    //karing://connect
    //karing://disconnect
    //karing://reconnect
    //karing://install-config?url=xxx&name=xxx&&isp-name=xxx&isp-url=xxx&isp-faq=xxx ;connect; disconnect; reconnect;
    //karing://install-config?url=https%3A%2F%2Fxn--xxxxx.com%2Fsub%2Fa363e83fd1f559df%2Fclash&name=gdy&&isp-name=%E8%B7%9F%E6%96%97%E4%BA%91&isp-url=https%3A%2F%2Fxn--9kq147c4p2a.com%2Fuser&isp-faq=
    //karing://restore-backup?url=https%3A%2F%2Fxn--xxxxx.com%2Fsub%2Fa363e83fd1f559df%2Fclash
    //karing://tvos?ips=192.168.1.102&port=4040&uuid=728EC1AB-7AC8-4E8F-8406-3856F6C70506&cport=3057&secret=0191eee9f89d7cd29fda94c0b663efb2&version=1.0.29.293
    Uri? uri = Uri.tryParse(url);
    if (uri == null) {
      return ReturnResultError("parse url failed: $url");
    }
    if (uri.isScheme(SystemSchemeUtils.getClashScheme())) {
      if (uri.host == "install-config") {
        return await _installConfig(context, uri);
      }
    } else if (uri.isScheme(SystemSchemeUtils.getSingboxScheme())) {
      if (uri.host == "import-remote-profile") {
        return await _installConfig(context, uri);
      }
    } else if (uri.isScheme(SystemSchemeUtils.getKaringScheme())) {
      if (uri.host == AppSchemeActions.connectAction()) {
        if (vpnConnect != null) {
          vpnConnect!.call();
        }
        return null;
      } else if (uri.host == AppSchemeActions.disconnectAction()) {
        if (vpnDisconnect != null) {
          vpnDisconnect!.call();
        }
        return null;
      } else if (uri.host == AppSchemeActions.reconnectAction()) {
        if (vpnReconnect != null) {
          vpnReconnect!.call();
        }
        return null;
      } else if (uri.host == AppSchemeActions.installConfigAction()) {
        return await _installConfig(context, uri);
      } else if (uri.host == AppSchemeActions.restoreBackup()) {
        return await _restoreBackup(context, uri);
      } else if (uri.host == AppSchemeActions.appleTVHost()) {
        if (PlatformUtils.isMobile()) {
          return GroupHelper.showAppleTVByUrl(context, url);
        }
      } else {
        return ReturnResultError("unsupport action: ${uri.host}");
      }
    }
    return ReturnResultError("unsupport scheme: ${uri.scheme}");
  }

  static Future<ReturnResultError?> _installConfig(
      BuildContext context, Uri uri) async {
    String? name;
    String? url;
    String? ispName;
    String? ispUrl;
    String? ispFaq;
    try {
      name = uri.queryParameters["name"];
      url = uri.queryParameters["url"];
      ispName =
          uri.queryParameters["isp-name"] ?? uri.queryParameters["Isp-Name"];
      ispUrl = uri.queryParameters["isp-url"] ?? uri.queryParameters["Isp-Url"];
      ispFaq = uri.queryParameters["isp-faq"] ?? uri.queryParameters["Isp-Faq"];
    } catch (err) {
      DialogUtils.showAlertDialog(context, err.toString(),
          showCopy: true, showFAQ: true, withVersion: true);
      return ReturnResultError(err.toString());
    }
    name ??= uri.fragment;
    if (name.isNotEmpty) {
      try {
        name = Uri.decodeComponent(name);
      } catch (err) {}
    }
    if (url != null) {
      try {
        url = Uri.decodeComponent(url);
      } catch (err) {}
    }

    return await _addConfigBySubscriptionLink(
        context, url, name, ispName, ispUrl, ispFaq);
  }

  static Future<ReturnResultError?> _restoreBackup(
      BuildContext context, Uri uri) async {
    String? url = uri.queryParameters["url"];
    if (url != null) {
      try {
        url = Uri.decodeComponent(url);
      } catch (err) {}
    }
    if (url == null || url.isEmpty) {
      return ReturnResultError("decode query param url failed");
    }
    Uri? downloadUri = Uri.tryParse(url);
    if (downloadUri == null) {
      return ReturnResultError("parse query param url failed");
    }
    final tcontext = Translations.of(context);
    bool? ok = await DialogUtils.showConfirmDialog(
        context, tcontext.SettingsScreen.rewriteConfirm);
    if (ok != true) {
      return ReturnResultError("user reject to overwrite");
    }
    if (!context.mounted) {
      return ReturnResultError("page unmounted");
    }
    DialogUtils.showLoadingDialog(context, text: "");
    String dir = await PathUtils.cacheDir();
    String filePath = path.join(dir, BackupAndSyncUtils.getZipFileName());
    var result = await HttpUtils.httpDownload(
        downloadUri, filePath, null, null, const Duration(seconds: 10));

    if (!context.mounted) {
      return ReturnResultError("page unmounted");
    }
    Navigator.pop(context);
    if (result.error != null) {
      DialogUtils.showAlertDialog(context, result.error!.message,
          showCopy: true, showFAQ: true, withVersion: true);
      return ReturnResultError(result.error!.message);
    }
    await GroupHelper.backupRestoreFromZip(context, filePath, confirm: false);
    await FileUtils.deleteFileByPath(filePath);
    return null;
  }

  static Future<ReturnResultError?> _addConfigBySubscriptionLink(
      BuildContext context,
      String? installUrl,
      String? name,
      String? ispName,
      String? ispUrl,
      String? ispFaq) async {
    int kMaxPush = 1;
    if (installUrl != null &&
        AddProfileByLinkOrContentScreen.pushed <= kMaxPush) {
      UrlLauncherUtils.closeWebview();
      bool? ok = await Navigator.push(
          context,
          MaterialPageRoute(
              settings: AddProfileByLinkOrContentScreen.routSettings(),
              builder: (context) => AddProfileByLinkOrContentScreen(
                  name: name,
                  linkUrl: installUrl,
                  ispName: ispName,
                  ispUrl: ispUrl,
                  ispFaq: ispFaq)));
      if (ok != true) {
        return ReturnResultError("addprofile failed or canceled by user");
      }
      return null;
    }
    return ReturnResultError("addprofile request already exists");
  }
}
