import 'dart:async';

import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api_trezor.dart';
import 'package:web_dex/mm2/mm2_api/rpc/trezor/balance/trezor_balance_init/trezor_balance_init_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/trezor/balance/trezor_balance_init/trezor_balance_init_response.dart';
import 'package:web_dex/mm2/mm2_api/rpc/trezor/balance/trezor_balance_status/trezor_balance_status_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/trezor/balance/trezor_balance_status/trezor_balance_status_response.dart';
import 'package:web_dex/mm2/mm2_api/rpc/trezor/enable_utxo/trezor_enable_utxo/trezor_enable_utxo_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/trezor/enable_utxo/trezor_enable_utxo/trezor_enable_utxo_response.dart';
import 'package:web_dex/mm2/mm2_api/rpc/trezor/enable_utxo/trezor_enable_utxo_status/trezor_enable_utxo_status_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/trezor/enable_utxo/trezor_enable_utxo_status/trezor_enable_utxo_status_response.dart';
import 'package:web_dex/mm2/mm2_api/rpc/trezor/get_new_address/get_new_address_response.dart';
import 'package:web_dex/mm2/mm2_api/rpc/trezor/init/init_trezor/init_trezor_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/trezor/init/init_trezor/init_trezor_response.dart';
import 'package:web_dex/mm2/mm2_api/rpc/trezor/init/init_trezor_cancel/init_trezor_cancel_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/trezor/init/init_trezor_status/init_trezor_status_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/trezor/init/init_trezor_status/init_trezor_status_response.dart';
import 'package:web_dex/mm2/mm2_api/rpc/trezor/trezor_passphrase/trezor_passphrase_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/trezor/trezor_pin/trezor_pin_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/trezor/withdraw/trezor_withdraw/trezor_withdraw_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/trezor/withdraw/trezor_withdraw/trezor_withdraw_response.dart';
import 'package:web_dex/mm2/mm2_api/rpc/trezor/withdraw/trezor_withdraw_cancel/trezor_withdraw_cancel_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/trezor/withdraw/trezor_withdraw_status/trezor_withdraw_status_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/trezor/withdraw/trezor_withdraw_status/trezor_withdraw_status_response.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/hw_wallet/trezor_connection_status.dart';
import 'package:web_dex/model/hw_wallet/trezor_task.dart';

class TrezorRepo {
  TrezorRepo({
    required Mm2ApiTrezor api,
  }) : _api = api;

  final Mm2ApiTrezor _api;

  Future<InitTrezorRes> init() async {
    return await _api.init(InitTrezorReq());
  }

  final StreamController<TrezorConnectionStatus> _connectionStatusController =
      StreamController<TrezorConnectionStatus>.broadcast();
  Stream<TrezorConnectionStatus> get connectionStatusStream =>
      _connectionStatusController.stream;
  Timer? _connectionStatusTimer;

  Future<InitTrezorStatusRes> initStatus(int taskId) async {
    return await _api.initStatus(InitTrezorStatusReq(taskId: taskId));
  }

  Future<void> sendPin(String pin, TrezorTask trezorTask) async {
    await _api.pin(TrezorPinRequest(
      pin: pin,
      task: trezorTask,
    ));
  }

  Future<void> sendPassphrase(String passphrase, TrezorTask trezorTask) async {
    await _api.passphrase(TrezorPassphraseRequest(
      passphrase: passphrase,
      task: trezorTask,
    ));
  }

  Future<void> initCancel(int taskId) async {
    await _api.initCancel(InitTrezorCancelReq(taskId: taskId));
  }

  Future<TrezorBalanceInitResponse> initBalance(Coin coin) async {
    return await _api.balanceInit(TrezorBalanceInitRequest(coin: coin));
  }

  Future<TrezorBalanceStatusResponse> getBalanceStatus(int taskId) async {
    return await _api.balanceStatus(TrezorBalanceStatusRequest(taskId: taskId));
  }

  Future<TrezorEnableUtxoResponse> enableUtxo(Coin coin) async {
    return await _api.enableUtxo(TrezorEnableUtxoReq(coin: coin));
  }

  Future<TrezorEnableUtxoStatusResponse> getEnableUtxoStatus(int taskId) async {
    return await _api
        .enableUtxoStatus(TrezorEnableUtxoStatusReq(taskId: taskId));
  }

  Future<TrezorGetNewAddressInitResponse> initNewAddress(String coin) async {
    return await _api.initNewAddress(coin);
  }

  Future<GetNewAddressResponse> getNewAddressStatus(int taskId) async {
    return await _api.getNewAddressStatus(taskId);
  }

  Future<void> cancelGetNewAddress(int taskId) async {
    await _api.cancelGetNewAddress(taskId);
  }

  Future<TrezorWithdrawResponse> withdraw(TrezorWithdrawRequest request) async {
    return await _api.withdraw(request);
  }

  Future<TrezorWithdrawStatusResponse> getWithdrawStatus(int taskId) async {
    return _api.withdrawStatus(TrezorWithdrawStatusRequest(taskId: taskId));
  }

  Future<void> cancelWithdraw(int taskId) async {
    await _api.withdrawCancel(TrezorWithdrawCancelRequest(taskId: taskId));
  }

  void subscribeOnConnectionStatus(String pubKey) {
    if (_connectionStatusTimer != null) return;
    _connectionStatusTimer =
        Timer.periodic(const Duration(seconds: 1), (timer) async {
      final TrezorConnectionStatus status =
          await _api.getConnectionStatus(pubKey);
      _connectionStatusController.sink.add(status);
      if (status == TrezorConnectionStatus.unreachable) {
        _connectionStatusTimer?.cancel();
        _connectionStatusTimer = null;
      }
    });
  }

  void unsubscribeFromConnectionStatus() {
    if (_connectionStatusTimer == null) return;
    _connectionStatusTimer?.cancel();
    _connectionStatusTimer = null;
  }
}

final TrezorRepo trezorRepo = TrezorRepo(api: mm2Api.trezor);
