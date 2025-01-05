import 'package:flutter/material.dart';
import 'package:web_dex/blocs/blocs.dart';
import 'package:web_dex/dispatchers/popup_dispatcher.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/views/common/wallet_password_dialog/password_dialog_content.dart';

// Shows wallet password dialog and
// returns password value or null (if wrong or cancelled)
Future<String?> walletPasswordDialog(
  BuildContext context, {
  Wallet? wallet,
}) async {
  wallet ??= currentWalletBloc.wallet;
  late PopupDispatcher popupManager;
  bool isOpen = false;
  String? password;

  void close() {
    popupManager.close();
    isOpen = false;
  }

  popupManager = PopupDispatcher(
    context: context,
    popupContent: PasswordDialogContent(
      wallet: wallet,
      onSuccess: (String pass) {
        password = pass;
        close();
      },
      onCancel: close,
    ),
  );

  isOpen = true;
  popupManager.show();

  while (isOpen) {
    await Future<dynamic>.delayed(const Duration(milliseconds: 100));
  }

  return password;
}