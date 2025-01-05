import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:komodo_cex_market_data/src/binance/models/binance_exchange_info.dart';
import 'package:komodo_cex_market_data/src/binance/models/binance_exchange_info_reduced.dart';
import 'package:komodo_cex_market_data/src/models/coin_ohlc.dart';

/// A provider class for fetching data from the Binance API.
class BinanceProvider {
  /// Creates a new BinanceProvider instance.
  const BinanceProvider({this.apiUrl = 'https://api.binance.us/api/v3'});

  /// The base URL for the Binance API.
  /// Defaults to 'https://api.binance.com/api/v3'.
  final String apiUrl;

  /// Fetches candlestick chart data from Binance API.
  ///
  /// Retrieves the candlestick chart data for a specific symbol and interval
  /// from the Binance API.
  /// Optionally, you can specify the start time, end time, and limit of the
  /// data to fetch.
  ///
  /// Parameters:
  /// - [symbol]: The trading symbol for which to fetch the candlestick
  /// chart data.
  /// - [interval]: The time interval for the candlestick chart data
  /// (e.g., '1m', '1h', '1d').
  /// - [startTime]: The start time (in milliseconds since epoch, Unix time) of
  /// the data range to fetch (optional).
  /// - [endTime]: The end time (in milliseconds since epoch, Unix time) of the
  /// data range to fetch (optional).
  /// - [limit]: The maximum number of data points to fetch (optional). Defaults
  /// to 500, maximum is 1000.
  ///
  /// Returns:
  /// A [Future] that resolves to a [CoinOhlc] object containing the fetched
  /// candlestick chart data.
  ///
  /// Example usage:
  /// ```dart
  /// final BinanceKlinesResponse klines = await fetchKlines(
  ///   'BTCUSDT',
  ///   '1h',
  ///   limit: 100,
  /// );
  /// ```
  ///
  /// Throws:
  /// - [Exception] if the API request fails.
  Future<CoinOhlc> fetchKlines(
    String symbol,
    String interval, {
    int? startUnixTimestampMilliseconds,
    int? endUnixTimestampMilliseconds,
    int? limit,
    String? baseUrl,
  }) async {
    final queryParameters = <String, dynamic>{
      'symbol': symbol,
      'interval': interval,
      if (startUnixTimestampMilliseconds != null)
        'startTime': startUnixTimestampMilliseconds.toString(),
      if (endUnixTimestampMilliseconds != null)
        'endTime': endUnixTimestampMilliseconds.toString(),
      if (limit != null) 'limit': limit.toString(),
    };

    final baseRequestUrl = baseUrl ?? apiUrl;
    final uri = Uri.parse('$baseRequestUrl/klines')
        .replace(queryParameters: queryParameters);

    final response = await http.get(uri);
    if (response.statusCode == 200) {
      return CoinOhlc.fromJson(
        jsonDecode(response.body) as List<dynamic>,
      );
    } else {
      throw Exception(
        'Failed to load klines: ${response.statusCode} ${response.body}',
      );
    }
  }

  /// Fetches the exchange information from Binance.
  ///
  /// Returns a [Future] that resolves to a [BinanceExchangeInfoResponse] object
  /// Throws an [Exception] if the request fails.
  Future<BinanceExchangeInfoResponse> fetchExchangeInfo({
    String? baseUrl,
  }) async {
    final requestUrl = baseUrl ?? apiUrl;
    final response = await http.get(Uri.parse('$requestUrl/exchangeInfo'));

    if (response.statusCode == 200) {
      return BinanceExchangeInfoResponse.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } else {
      throw http.ClientException(
        'Failed to load exchange info: ${response.statusCode} ${response.body}',
      );
    }
  }

  /// Fetches the exchange information from Binance.
  ///
  /// Returns a [Future] that resolves to a [BinanceExchangeInfoResponseReduced]
  /// object.
  /// Throws an [Exception] if the request fails.
  Future<BinanceExchangeInfoResponseReduced> fetchExchangeInfoReduced({
    String? baseUrl,
  }) async {
    final requestUrl = baseUrl ?? apiUrl;
    final response = await http.get(Uri.parse('$requestUrl/exchangeInfo'));

    if (response.statusCode == 200) {
      return BinanceExchangeInfoResponseReduced.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } else if (response.statusCode == 451) {
      // service unavailable for legal reasons
      return BinanceExchangeInfoResponseReduced(
        timezone: '',
        serverTime: 0,
        symbols: List.empty(),
      );
    } else {
      throw http.ClientException(
        'Failed to load exchange info: ${response.statusCode} ${response.body}',
      );
    }
  }
}
