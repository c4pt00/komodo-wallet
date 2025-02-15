import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/transaction_history/transaction_history_bloc.dart';
import 'package:web_dex/bloc/transaction_history/transaction_history_event.dart';
import 'package:web_dex/blocs/blocs.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/views/wallet/coin_details/coin_details_info/coin_details_info.dart';
import 'package:web_dex/views/wallet/coin_details/coin_page_type.dart';
import 'package:web_dex/views/wallet/coin_details/faucet/faucet_page.dart';
import 'package:web_dex/views/wallet/coin_details/receive/receive_details.dart';
import 'package:web_dex/views/wallet/coin_details/rewards/kmd_reward_claim_success.dart';
import 'package:web_dex/views/wallet/coin_details/rewards/kmd_rewards_info.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/withdraw_form.dart';

class CoinDetails extends StatefulWidget {
  const CoinDetails({
    Key? key,
    required this.coin,
    required this.onBackButtonPressed,
  }) : super(key: key);

  final Coin coin;
  final VoidCallback onBackButtonPressed;

  @override
  State<CoinDetails> createState() => _CoinDetailsState();
}

class _CoinDetailsState extends State<CoinDetails> {
  late TransactionHistoryBloc _txHistoryBloc;
  CoinPageType _selectedPageType = CoinPageType.info;

  String _rewardValue = '';
  String _formattedUsdPrice = '';

  @override
  void initState() {
    _txHistoryBloc = context.read<TransactionHistoryBloc>();
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      context
          .read<TransactionHistoryBloc>()
          .add(TransactionHistorySubscribe(coin: widget.coin));
    });
    super.initState();
  }

  @override
  void dispose() {
    _txHistoryBloc.add(TransactionHistoryUnsubscribe(coin: widget.coin));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Iterable<Coin>>(
      initialData: coinsBloc.walletCoinsMap.values,
      stream: coinsBloc.outWalletCoins,
      builder: (context, AsyncSnapshot<Iterable<Coin>> snapshot) {
        return _buildContent();
      },
    );
  }

  Widget _buildContent() {
    switch (_selectedPageType) {
      case CoinPageType.info:
        return CoinDetailsInfo(
          coin: widget.coin,
          setPageType: _setPageType,
          onBackButtonPressed: widget.onBackButtonPressed,
        );

      case CoinPageType.send:
        return WithdrawForm(
          coin: widget.coin,
          onBackButtonPressed: _openInfo,
          onSuccess: () => _setPageType(CoinPageType.info),
        );

      case CoinPageType.receive:
        return ReceiveDetails(
          coin: widget.coin,
          onBackButtonPressed: _openInfo,
        );

      case CoinPageType.faucet:
        return FaucetPage(
          coinAbbr: widget.coin.abbr,
          onBackButtonPressed: _openInfo,
          coinAddress: widget.coin.defaultAddress,
        );

      case CoinPageType.claim:
        return KmdRewardsInfo(
          coin: widget.coin,
          onBackButtonPressed: _openInfo,
          onSuccess: (String reward, String formattedUsd) {
            _rewardValue = reward;
            _formattedUsdPrice = formattedUsd;
            _setPageType(CoinPageType.claimSuccess);
          },
        );

      case CoinPageType.claimSuccess:
        return KmdRewardClaimSuccess(
          reward: _rewardValue,
          formattedUsd: _formattedUsdPrice,
          onBackButtonPressed: _openInfo,
        );
    }
  }

  void _openInfo() => _setPageType(CoinPageType.info);

  void _setPageType(CoinPageType pageType) {
    setState(() => _selectedPageType = pageType);
  }
}
