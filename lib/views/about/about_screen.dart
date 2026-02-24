import 'package:app/extension/context_extension.dart';
import 'package:app/utils/assets_util.dart';
import 'package:app/views/ui/app_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../generated/l10n.dart';
import '../ui/bud_icon.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = "";

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _loadVersionInfo());
  }

  Future<void> _loadVersionInfo() async {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();

    setState(() {
      _version = packageInfo.version;
    });
  }

  void _openUrl(String url) {
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _openEmail(String email) {
    launchUrl(
      Uri(scheme: 'mailto', path: email),
      mode: LaunchMode.externalApplication,
    );
  }

  late final _shareInfoList = <_InfoData>[
    _InfoData(AssetsUtil.icon_official_website, 'Portfolio', () {
      _openUrl('https://hiibrarahmad.github.io/');
    }),
    _InfoData(AssetsUtil.icon_facebook, 'LinkedIn', () {
      _openUrl('https://linkedin.com/in/hiibrarahmad');
    }),
    _InfoData(AssetsUtil.icon_login_email, 'Email', () {
      _openEmail('hiibrarahmad@gmail.com');
    }),
    _InfoData(AssetsUtil.icon_about, 'GitHub', () {
      _openUrl('https://github.com/hiibrarahmad');
    }),
    _InfoData(AssetsUtil.icon_twitter, 'X', () {
      _openUrl('https://twitter.com/hiibrarahmad');
    }),
    _InfoData(AssetsUtil.icon_instagram, 'Instagram', () {
      _openUrl('https://instagram.com/hiibrarahmad');
    }),
    _InfoData(AssetsUtil.icon_youtube, 'YouTube', () {
      _openUrl('https://youtube.com/@hiibrarahmad');
    }),
  ];

  List<_InfoData> get _appInfoList => [
    _InfoData(
      AssetsUtil.icon_about,
      S.of(context).pageAboutVersion(_version),
      () {},
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: DefaultTextStyle(
            style: TextStyle(
              color: context.isLightMode ? Colors.black : Colors.white,
            ),
            child: Column(
              children: [
                _buildAppbar(context),
                SizedBox(height: 17.h),
                Image.asset(
                  AssetsUtil.logo_hd,
                  width: 116.r,
                  height: 106.r,
                  filterQuality: FilterQuality.low,
                  gaplessPlayback: true,
                ),
                SizedBox(height: 9.h),
                Text(
                  S.of(context).appName,
                  style: TextStyle(
                    fontSize: 24.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 18.h),
                Text(
                  'Connect with Ibrar Ahmad',
                  style: TextStyle(fontSize: 14.sp),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(16.r),
                    child: Column(
                      children: [
                        Flexible(
                          child: _buildInfoGroup(context, _shareInfoList, true),
                        ),
                        SizedBox(height: 16.h),
                        _buildInfoGroup(context, _appInfoList, false),
                      ],
                    ),
                  ),
                ),
                DefaultTextStyle(
                  style: TextStyle(
                    color: const Color(0xff29BBC6),
                    fontSize: 12.sp,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () {
                          _openUrl('https://github.com/hiibrarahmad');
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: const Text('GitHub'),
                        ),
                      ),
                      const Text('  |  '),
                      GestureDetector(
                        onTap: () {
                          _openUrl('https://linkedin.com/in/hiibrarahmad');
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: const Text('LinkedIn'),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 17.h),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppbar(BuildContext context) {
    return SizedBox(
      height: 40.r,
      child: Stack(
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: GestureDetector(
              onTap: () => context.pop(),
              child: Padding(
                padding: EdgeInsets.all(10.r),
                child: BudIcon(icon: AssetsUtil.icon_arrow_back, size: 20.r),
              ),
            ),
          ),
          Center(
            child: Text(
              S.of(context).pageAboutTitle,
              style: TextStyle(
                color: context.isLightMode ? Colors.black : Colors.white,
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoGroup(
    BuildContext context,
    List<_InfoData> infoList,
    bool scrollable,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: context.isLightMode ? Colors.white : const Color(0xff394044),
        borderRadius: BorderRadius.circular(8).r,
      ),
      padding: EdgeInsets.symmetric(horizontal: 16.r),
      child: ListView.separated(
        shrinkWrap: true,
        physics: scrollable
            ? const ClampingScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        itemCount: infoList.length,
        itemBuilder: (context, index) {
          final info = infoList[index];
          return GestureDetector(
            onTap: info.onTap,
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              height: 52,
              child: Row(
                children: [
                  BudIcon(icon: info.icon, size: 20.r),
                  SizedBox(width: 15.w),
                  Text(
                    info.title,
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        separatorBuilder: (context, index) {
          return Divider(
            height: 1,
            color: context.isLightMode
                ? Colors.black.withAlpha(10)
                : Colors.white.withAlpha(10),
          );
        },
      ),
    );
  }
}

class _InfoData {
  final String icon;
  final String title;
  final VoidCallback onTap;

  _InfoData(this.icon, this.title, this.onTap);
}
