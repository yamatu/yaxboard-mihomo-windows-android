import 'package:fl_clash/xboard/features/auth/auth.dart';
import 'package:fl_clash/xboard/infrastructure/providers/repository_providers.dart';
import 'package:fl_clash/common/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fl_clash/xboard/utils/xboard_notification.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/xboard/features/shared/shared.dart';
import 'package:fl_clash/xboard/services/services.dart';
import 'package:fl_clash/xboard/sdk/xboard_sdk.dart' show ConfigData;
import 'package:go_router/go_router.dart';
class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});
  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}
class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _inviteCodeController = TextEditingController();
  final _emailCodeController = TextEditingController();
  bool _isRegistering = false;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isSendingEmailCode = false;
  
  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _inviteCodeController.dispose();
    _emailCodeController.dispose();
    super.dispose();
  }
  Future<void> _register() async {
    // 获取配置
    final configAsync = ref.read(configProvider);
    final config = configAsync.value;
    final isInviteForce = config?.isInviteForce ?? false;
    final isEmailVerify = config?.isEmailVerify ?? false;
    
    // 检查邮请码是否必填
    if (isInviteForce && _inviteCodeController.text.trim().isEmpty) {
      _showInviteCodeDialog();
      return;
    }
    
    // 检查邮箱验证码是否必填
    if (isEmailVerify && _emailCodeController.text.trim().isEmpty) {
      XBoardNotification.showError('请输入邮箱验证码');
      return;
    }

    if (_formKey.currentState!.validate()) {
      setState(() {
        _isRegistering = true;
      });
      try {
        // 使用 AuthRepository 注册
        final authRepo = ref.read(authRepositoryProvider);
        final result = await authRepo.register(
          email: _emailController.text,
          password: _passwordController.text,
          inviteCode: _inviteCodeController.text.trim().isNotEmpty 
              ? _inviteCodeController.text 
              : null,
          emailCode: isEmailVerify && _emailCodeController.text.trim().isNotEmpty
              ? _emailCodeController.text
              : null,
        );
        
        if (result.isFailure) {
          throw Exception(result.exceptionOrNull?.message ?? '注册失败');
        }
        
        // 注册成功
        if (mounted) {
          final storageService = ref.read(storageServiceProvider);
          await storageService.saveCredentials(
            _emailController.text,
            _passwordController.text,
            true, // 启用记住密码
          );
          if (mounted) {
            XBoardNotification.showSuccess(appLocalizations.xboardRegisterSuccess);
          }
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) {
              context.pop();
            }
          });
        }
      } catch (e) {
        if (mounted) {
          // 提取详细的错误信息
          String errorMessage = '注册失败';
          
          final errorStr = e.toString();
          
          // 尝试提取具体的错误信息
          if (errorStr.contains('XBoardException')) {
            // 格式1: XBoardException(400): 具体错误信息
            if (errorStr.contains('): ')) {
              final parts = errorStr.split('): ');
              if (parts.length > 1) {
                errorMessage = parts.sublist(1).join('): ').trim();
              }
            } 
            // 格式2: XBoardException: 具体错误信息
            else if (errorStr.contains('XBoardException: ')) {
              errorMessage = errorStr.split('XBoardException: ').last.trim();
            }
          } else {
            // 其他类型的错误，直接使用错误文本
            errorMessage = errorStr;
          }
          
          // 移除可能的 "Error: " 前缀
          if (errorMessage.startsWith('Error: ')) {
            errorMessage = errorMessage.substring(7);
          }
          
          // 500错误或通用错误提示：可能是邀请码问题
          if (errorMessage.contains('遇到了些问题') || errorMessage.contains('500')) {
            errorMessage = appLocalizations.inviteCodeIncorrect;
          }
          
          XBoardNotification.showError(errorMessage);
        }
      } finally {
        if (mounted) {
          setState(() {
            _isRegistering = false;
          });
        }
      }
    }
  }

  Future<void> _sendEmailCode() async {
    if (_emailController.text.isEmpty) {
      XBoardNotification.showError(appLocalizations.pleaseEnterEmailAddress);
      return;
    }

    if (!_emailController.text.contains('@')) {
      XBoardNotification.showError(appLocalizations.pleaseEnterValidEmailAddress);
      return;
    }

    setState(() {
      _isSendingEmailCode = true;
    });

    try {
      // 使用 AuthRepository 发送验证码
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.sendVerificationCode(_emailController.text);

      if (mounted) {
        XBoardNotification.showSuccess(appLocalizations.verificationCodeSentCheckEmail);
      }
    } catch (e) {
      if (mounted) {
        XBoardNotification.showError(appLocalizations.sendVerificationCodeFailed(e.toString()));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSendingEmailCode = false;
        });
      }
    }
  }

  void _showInviteCodeDialog() {
    showCupertinoDialog(
      context: context,
      builder: (BuildContext context) {
        return CupertinoAlertDialog(
          title: Text(appLocalizations.inviteCodeRequired),
          content: Text(appLocalizations.inviteCodeRequiredMessage),
          actions: [
            CupertinoDialogAction(
              onPressed: () {
                context.pop();
              },
              child: Text(appLocalizations.iUnderstand),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = CupertinoDynamicColor.resolve(CupertinoColors.systemBackground, context);
    final configAsync = ref.watch(configProvider);

    // 处理异步加载状态
    return configAsync.when(
      loading: () => Scaffold(
        backgroundColor: bgColor,
        body: const Center(child: CupertinoActivityIndicator()),
      ),
      error: (error, stack) => _buildPage(context, null),
      data: (config) => _buildPage(context, config),
    );
  }
  
  Widget _buildPage(BuildContext context, ConfigData? config) {
    final primaryColor = CupertinoTheme.of(context).primaryColor;
    final labelColor = CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final textColor = CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final bgColor = CupertinoDynamicColor.resolve(CupertinoColors.systemBackground, context);

    return Scaffold(
      backgroundColor: bgColor,
      body: XBContainer(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => context.pop(),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: CupertinoDynamicColor.resolve(CupertinoColors.tertiarySystemFill, context),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(CupertinoIcons.back, color: textColor),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    appLocalizations.createAccount,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          appLocalizations.fillInfoToRegister,
                          style: TextStyle(
                            fontSize: 15,
                            color: labelColor,
                          ),
                        ),
                        const SizedBox(height: 32),
                        XBInputField(
                          controller: _emailController,
                          labelText: appLocalizations.emailAddress,
                          hintText: appLocalizations.pleaseEnterYourEmailAddress,
                          prefixIcon: CupertinoIcons.mail,
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return appLocalizations.pleaseEnterEmailAddress;
                            }
                            if (!value.contains('@')) {
                              return appLocalizations.pleaseEnterValidEmailAddress;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        XBInputField(
                          controller: _passwordController,
                          labelText: appLocalizations.password,
                          hintText: appLocalizations.pleaseEnterAtLeast8CharsPassword,
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
                              return appLocalizations.pleaseEnterPassword;
                            }
                            if (value.length < 8) {
                              return appLocalizations.passwordMin8Chars;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        XBInputField(
                          controller: _confirmPasswordController,
                          labelText: appLocalizations.confirmNewPassword,
                          hintText: appLocalizations.pleaseReEnterPassword,
                          prefixIcon: CupertinoIcons.lock,
                          obscureText: !_isConfirmPasswordVisible,
                          suffixIcon: CupertinoButton(
                            padding: EdgeInsets.zero,
                            child: Icon(
                              _isConfirmPasswordVisible
                                  ? CupertinoIcons.eye
                                  : CupertinoIcons.eye_slash,
                              color: labelColor,
                            ),
                            onPressed: () {
                              setState(() {
                                _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
                              });
                            },
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return appLocalizations.pleaseConfirmPassword;
                            }
                            if (value != _passwordController.text) {
                              return appLocalizations.passwordsDoNotMatch;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        // 根据配置决定是否显示邮箱验证码字段
                        if (config?.isEmailVerify == true)
                          Column(
                            children: [
                                  XBInputField(
                                    controller: _emailCodeController,
                                    labelText: appLocalizations.emailVerificationCode,
                                    hintText: appLocalizations.pleaseEnterEmailVerificationCode,
                                    prefixIcon: CupertinoIcons.checkmark_shield,
                                    keyboardType: TextInputType.number,
                                    suffixIcon: _isSendingEmailCode
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CupertinoActivityIndicator(),
                                          )
                                        : CupertinoButton(
                                            padding: EdgeInsets.zero,
                                            onPressed: _sendEmailCode,
                                            child: Text(appLocalizations.sendVerificationCode),
                                          ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return appLocalizations.pleaseEnterEmailVerificationCode;
                                      }
                                      if (value.length != 6) {
                                        return appLocalizations.verificationCode6Digits;
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 20),
                            ],
                          ),
                        // 邀请码：始终显示，根据配置改变标签（必填 vs 可选）
                        XBInputField(
                          controller: _inviteCodeController,
                          labelText: (config?.isInviteForce ?? false)
                              ? '${appLocalizations.xboardInviteCode} *'
                              : appLocalizations.inviteCodeOptional,
                          hintText: appLocalizations.pleaseEnterInviteCode,
                          prefixIcon: CupertinoIcons.gift,
                          enabled: true,
                        ),
                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: _isRegistering
                              ? CupertinoButton.filled(
                                  onPressed: null,
                                  padding: EdgeInsets.zero,
                                  child: const CupertinoActivityIndicator(
                                    color: CupertinoColors.white,
                                  ),
                                )
                              : CupertinoButton.filled(
                                  onPressed: _register,
                                  padding: EdgeInsets.zero,
                                  child: Text(
                                    appLocalizations.registerAccount,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              appLocalizations.alreadyHaveAccount,
                              style: TextStyle(
                                fontSize: 15,
                                color: labelColor,
                              ),
                            ),
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: () => context.pop(),
                              child: Text(
                                appLocalizations.loginNow,
                                style: TextStyle(
                                  color: primaryColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
} 