import 'dart:io';

import 'package:fl_clash/xboard/services/services.dart';
import 'package:fl_clash/xboard/features/auth/providers/xboard_user_provider.dart';
import 'package:fl_clash/xboard/features/domain_status/domain_status.dart';
import 'package:fl_clash/common/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'register_page.dart';
import 'forgot_password_page.dart';
import 'package:fl_clash/xboard/features/shared/shared.dart';
import 'package:fl_clash/xboard/config/utils/config_file_loader.dart';
import 'package:fl_clash/xboard/utils/xboard_notification.dart';
import 'package:fl_clash/xboard/sdk/xboard_sdk.dart';
import 'package:fl_clash/xboard/utils/app_recovery_service.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});
  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _rememberPassword = false;
  bool _isPasswordVisible = false;
  bool _isRepairing = false;
  late XBoardStorageService _storageService;

  // 从配置文件加载的应用信息
  String _appTitle = 'XBoard';
  String _appWebsite = 'example.com';

  @override
  void initState() {
    super.initState();
    _storageService = ref.read(storageServiceProvider);
    _loadSavedCredentials();
    _checkDomainStatus();
    _loadAppInfo();
  }

  /// 加载应用信息（标题和网站）
  Future<void> _loadAppInfo() async {
    final title = await ConfigFileLoaderHelper.getAppTitle();
    final website = await ConfigFileLoaderHelper.getAppWebsite();
    if (mounted) {
      setState(() {
        _appTitle = title;
        _appWebsite = website;
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkDomainStatus() async {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(domainStatusProvider.notifier).checkDomain();
    });
  }

  Future<void> _flushDnsAndRetry() async {
    if (!Platform.isWindows || _isRepairing) return;
    setState(() {
      _isRepairing = true;
    });
    try {
      await AppRecoveryService.flushDnsCache();
      // Force a clean re-init path.
      XBoardSDK.dispose();
      await ref.read(domainStatusProvider.notifier).refresh();
      XBoardNotification.showSuccess('网络已刷新');
    } catch (e) {
      XBoardNotification.showError('网络刷新失败：$e');
    } finally {
      if (mounted) {
        setState(() {
          _isRepairing = false;
        });
      }
    }
  }

  Future<void> _showRepairDialog() async {
    if (!Platform.isWindows || _isRepairing) return;
    await showCupertinoDialog<void>(
      context: context,
      builder: (context) {
        return CupertinoAlertDialog(
          title: const Text('网络修复'),
          content: const Text(
            '如果域名解析卡住（本地DNS缓存仍是旧IP），你可以刷新DNS并重试，或者彻底重启软件。',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(appLocalizations.cancel),
            ),
            CupertinoDialogAction(
              onPressed: () async {
                Navigator.of(context).pop();
                await _flushDnsAndRetry();
              },
              child: const Text('刷新DNS并重试'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: false,
              onPressed: () {
                Navigator.of(context).pop();
                AppRecoveryService.restartApp(
                  reason: 'login_page_repair',
                  flushDnsBeforeRestart: true,
                  resetSystemProxy: true,
                );
              },
              child: const Text('重启软件'),
            ),
          ],
        );
      },
    );
  }

  void refreshCredentials() {
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final savedEmail = await _storageService.getSavedEmail();
      final savedPassword = await _storageService.getSavedPassword();
      final rememberPassword = await _storageService.getRememberPassword();
      if (savedEmail != null && savedEmail.isNotEmpty) {
        _emailController.text = savedEmail;
      }
      if (savedPassword != null &&
          savedPassword.isNotEmpty &&
          rememberPassword) {
        _passwordController.text = savedPassword;
      }
      _rememberPassword = rememberPassword;
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      // 忽略加载凭据失败,继续正常流程
    }
  }

  Future<void> _login() async {
    if (_formKey.currentState!.validate()) {
      final authState = ref.read(xboardUserProvider);
      if (!authState.isInitialized || authState.isLoading) {
        return;
      }

      final userNotifier = ref.read(xboardUserProvider.notifier);
      final success = await userNotifier.login(
        _emailController.text,
        _passwordController.text,
      );
      if (mounted) {
        if (success) {
          if (_rememberPassword) {
            await _storageService.saveCredentials(
              _emailController.text,
              _passwordController.text,
              true,
            );
          } else {
            await _storageService.saveCredentials(
              _emailController.text,
              '',
              false,
            );
          }
          if (mounted) {
            XBoardNotification.showSuccess(appLocalizations.xboardLoginSuccess);
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted) {
                context.go('/');
              }
            });
          }
        } else {
          final userState = ref.read(xboardUserProvider);
          if (userState.errorMessage != null) {
            // 使用 FlClash 的原生 Toast 通知（自动消失）
            XBoardNotification.showError(userState.errorMessage!);
          }
        }
      }
    }
  }

  void _navigateToRegister() async {
    await Navigator.of(context).push(
      CupertinoPageRoute(builder: (context) => const RegisterPage()),
    );
    _loadSavedCredentials();
    _checkDomainStatus();
  }

  void _navigateToForgotPassword() async {
    await Navigator.of(context).push(
      CupertinoPageRoute(builder: (context) => const ForgotPasswordPage()),
    );
    _checkDomainStatus();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = CupertinoTheme.of(context).primaryColor;
    final labelColor = CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final textColor = CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final bgColor = CupertinoDynamicColor.resolve(CupertinoColors.systemBackground, context);
    final domainStatus = ref.watch(domainStatusProvider);
    final userState = ref.watch(xboardUserProvider);
    final isAuthChecking = !userState.isInitialized;
    final isBusy = userState.isLoading || isAuthChecking;
    final canSubmit = domainStatus.isReady && !isBusy;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (Platform.isWindows)
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _isRepairing ? null : _showRepairDialog,
              child: _isRepairing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CupertinoActivityIndicator(),
                    )
                  : const Icon(CupertinoIcons.restart, size: 22),
            ),
          const LanguageSelector(),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: GestureDetector(
              onTap: () => showDomainStatusDialog(context),
              child: const DomainStatusIndicator(),
            ),
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              bgColor,
              bgColor.withValues(alpha: 0.8),
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: primaryColor.withValues(alpha: 0.1),
                            ),
                            child: Icon(
                              CupertinoIcons.lock_shield,
                              size: 48,
                              color: primaryColor,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            _appTitle,
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _appWebsite,
                            style: TextStyle(
                              fontSize: 17,
                              color: labelColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 48),
                    XBInputField(
                      controller: _emailController,
                      labelText: appLocalizations.xboardEmail,
                      hintText: appLocalizations.xboardEmail,
                      prefixIcon: CupertinoIcons.mail,
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return appLocalizations.xboardEmail;
                        }
                        if (!value.contains('@')) {
                          return appLocalizations.xboardEmail;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    XBInputField(
                      controller: _passwordController,
                      labelText: appLocalizations.xboardPassword,
                      hintText: appLocalizations.xboardPassword,
                      prefixIcon: CupertinoIcons.lock,
                      obscureText: !_isPasswordVisible,
                      suffixIcon: CupertinoButton(
                        padding: EdgeInsets.zero,
                        child: Icon(
                          _isPasswordVisible
                              ? CupertinoIcons.eye
                              : CupertinoIcons.eye_slash,
                          color: labelColor,
                        ),
                        onPressed: () {
                          setState(() {
                            _isPasswordVisible = !_isPasswordVisible;
                          });
                        },
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return appLocalizations.xboardPassword;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        SizedBox(
                          height: 30,
                          child: CupertinoSwitch(
                            value: _rememberPassword,
                            activeTrackColor: primaryColor,
                            onChanged: (value) {
                              setState(() {
                                _rememberPassword = value;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _rememberPassword = !_rememberPassword;
                            });
                          },
                          child: Text(
                            appLocalizations.xboardRememberPassword,
                            style: TextStyle(
                              fontSize: 15,
                              color: textColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    if (isAuthChecking) ...[
                      Text(
                        '正在检查登录状态，请稍候...',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          color: labelColor,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(
                      height: 48,
                      child: CupertinoButton.filled(
                        onPressed: canSubmit ? _login : null,
                        padding: EdgeInsets.zero,
                        child: isBusy
                            ? const CupertinoActivityIndicator(
                                color: CupertinoColors.white,
                              )
                            : Text(appLocalizations.xboardLogin),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: _navigateToForgotPassword,
                          child: Text(
                            appLocalizations.xboardForgotPassword,
                          ),
                        ),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: _navigateToRegister,
                          child: Text(
                            appLocalizations.xboardRegister,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
