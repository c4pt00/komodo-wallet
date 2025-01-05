import 'package:flutter/material.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/blocs/blocs.dart';
import 'package:web_dex/views/dex/simple/form/exchange_info/exchange_rate.dart';

class MakerFormExchangeRate extends StatelessWidget {
  const MakerFormExchangeRate({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Rational?>(
        initialData: makerFormBloc.price,
        stream: makerFormBloc.outPrice,
        builder: (context, snapshot) {
          return ExchangeRate(
            base: makerFormBloc.sellCoin?.abbr,
            rel: makerFormBloc.buyCoin?.abbr,
            rate: snapshot.data,
          );
        });
  }
}