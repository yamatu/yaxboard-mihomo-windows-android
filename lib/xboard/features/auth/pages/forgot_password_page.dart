import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fl_clash/xboard/utils/xboard_notification.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/xboard/features/shared/shared.dart';
import 'package:fl_clash/xboard/infrastructure/providers/repository_providers.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:go_router/go_router.dart';

class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key});
  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

enum ResetPasswordStep {
  sendCode,    // 发送验证码步骤
  resetPassword // 重置密码步骤
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  ResetPasswordStep _currentStep = ResetPasswordStep.sendCode;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  
  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _sendVerificationCode() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });
    
    try {
      // 使用 AuthRepository 发送验证码
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.sendVerificationCode(_emailController.text);
      
      if (mounted) {
        setState(() {
          _currentStep = ResetPasswordStep.resetPassword;
        });
        XBoardNotification.showSuccess(AppLocalizations.of(context).verificationCodeSent);
      }
    } catch (e) {
      if (mounted) {
        XBoardNotification.showError('${AppLocalizations.of(context).sendCodeFailed}: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      XBoardNotification.showError(AppLocalizations.of(context).passwordMismatch);
      return;
    }

    setState(() {
      _isLoading = true;
    });
    
    try {
      // 使用 AuthRepository 重置密码
      final authRepo = ref.read(authRepositoryProvider);
      final result = await authRepo.resetPassword(
        email: _emailController.text,
        password: _passwordController.text,
        emailCode: _codeController.text,
      );
      
      if (result.isFailure) {
        throw Exception(result.exceptionOrNull?.message ?? '重置密码失败');
      }
      
      if (mounted) {
        XBoardNotification.showSuccess(AppLocalizations.of(context).passwordResetSuccessful);
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        XBoardNotification.showError('${AppLocalizations.of(context).passwordResetFailed}: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _goBackToSendCode() {
    setState(() {
      _currentStep = ResetPasswordStep.sendCode;
      _codeController.clear();
      _passwordController.clear();
      _confirmPasswordController.clear();
    });
  }
  Widget _buildSendCodeStep() {
    final labelColor = CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          AppLocalizations.of(context).enterEmailForReset,
          style: TextStyle(
            fontSize: 15,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 32),
        XBInputField(
          controller: _emailController,
          labelText: AppLocalizations.of(context).emailAddress,
          hintText: AppLocalizations.of(context).pleaseEnterEmail,
          prefixIcon: CupertinoIcons.mail,
          keyboardType: TextInputType.emailAddress,
          enabled: !_isLoading,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return AppLocalizations.of(context).pleaseEnterEmail;
            }
            if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
              return AppLocalizations.of(context).pleaseEnterValidEmail;
            }
            return null;
          },
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: _isLoading
              ? CupertinoButton.filled(
                  onPressed: null,
                  padding: EdgeInsets.zero,
                  child: const CupertinoActivityIndicator(
                    color: CupertinoColors.white,
                  ),
                )
              : CupertinoButton.filled(
                  onPressed: _sendVerificationCode,
                  padding: EdgeInsets.zero,
                  child: Text(
                    AppLocalizations.of(context).sendVerificationCode,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildResetPasswordStep() {
    final primaryColor = CupertinoTheme.of(context).primaryColor;
    final labelColor = CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          AppLocalizations.of(context).verificationCodeSentTo(_emailController.text),
          style: TextStyle(
            fontSize: 15,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 32),
        XBInputField(
          controller: _codeController,
          labelText: AppLocalizations.of(context).verificationCode,
          hintText: AppLocalizations.of(context).pleaseEnterVerificationCode,
          prefixIcon: CupertinoIcons.checkmark_shield,
          keyboardType: TextInputType.number,
          enabled: !_isLoading,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return AppLocalizations.of(context).pleaseEnterVerificationCode;
            }
            if (value.length < 4) {
              return AppLocalizations.of(context).pleaseEnterValidVerificationCode;
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        XBInputField(
          controller: _passwordController,
          labelText: AppLocalizations.of(context).newPassword,
          hintText: AppLocalizations.of(context).pleaseEnterNewPassword,
          prefixIcon: CupertinoIcons.lock,
          obscureText: _obscurePassword,
          enabled: !_isLoading,
          suffixIcon: CupertinoButton(
            padding: EdgeInsets.zero,
            child: Icon(
              _obscurePassword ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
              color: labelColor,
            ),
            onPressed: () {
              setState(() {
                _obscurePassword = !_obscurePassword;
              });
            },
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return AppLocalizations.of(context).pleaseEnterNewPassword;
            }
            if (value.length < 6) {
              return AppLocalizations.of(context).passwordMinLength;
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        XBInputField(
          controller: _confirmPasswordController,
          labelText: AppLocalizations.of(context).confirmNewPassword,
          hintText: AppLocalizations.of(context).pleaseConfirmNewPassword,
          prefixIcon: CupertinoIcons.lock,
          obscureText: _obscureConfirmPassword,
          enabled: !_isLoading,
          suffixIcon: CupertinoButton(
            padding: EdgeInsets.zero,
            child: Icon(
              _obscureConfirmPassword ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
              color: labelColor,
            ),
            onPressed: () {
              setState(() {
                _obscureConfirmPassword = !_obscureConfirmPassword;
              });
            },
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return AppLocalizations.of(context).pleaseConfirmNewPassword;
            }
            if (value != _passwordController.text) {
              return AppLocalizations.of(context).passwordMismatch;
            }
            return null;
          },
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: _isLoading
              ? CupertinoButton.filled(
                  onPressed: null,
                  padding: EdgeInsets.zero,
                  child: const CupertinoActivityIndicator(
                    color: CupertinoColors.white,
                  ),
                )
              : CupertinoButton.filled(
                  onPressed: _resetPassword,
                  padding: EdgeInsets.zero,
                  child: Text(
                    AppLocalizations.of(context).resetPassword,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 16),
        CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _isLoading ? null : _goBackToSendCode,
          child: Text(
            AppLocalizations.of(context).resendVerificationCode,
            style: TextStyle(
              color: primaryColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
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
                    onPressed: () {
                      if (_currentStep == ResetPasswordStep.resetPassword) {
                        _goBackToSendCode();
                      } else {
                        context.pop();
                      }
                    },
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
                    _currentStep == ResetPasswordStep.sendCode ? AppLocalizations.of(context).resetPassword : AppLocalizations.of(context).setNewPassword,
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
                        if (_currentStep == ResetPasswordStep.sendCode)
                          _buildSendCodeStep()
                        else
                          _buildResetPasswordStep(),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              AppLocalizations.of(context).rememberPassword,
                              style: TextStyle(
                                fontSize: 15,
                                color: labelColor,
                              ),
                            ),
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: () => context.pop(),
                              child: Text(
                                AppLocalizations.of(context).backToLogin,
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