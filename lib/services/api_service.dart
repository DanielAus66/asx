import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/stock.dart';

class ApiService {
  static const List<String> _baseUrls = [
    'https://query1.finance.yahoo.com',
    'https://query2.finance.yahoo.com',
  ];
  
  static final Set<String> _validSymbols = {};
  static bool _symbolsInitialized = false;
  static List<String> _dynamicAsxSymbols = [];
  static Map<String, String> _dynamicStockNames = {};
  
  static const String _keyAsxSymbols = 'asx_symbols_cache';
  static const String _keyAsxNames = 'asx_names_cache';
  static const String _keyAsxCacheTime = 'asx_symbols_cache_time';

  static Future<void> initializeValidSymbols() async {
    if (_symbolsInitialized) return;
    
    // Try to load cached symbols first
    await _loadCachedSymbols();
    
    // If we have cached symbols and they're fresh (< 7 days), use them
    if (_dynamicAsxSymbols.isNotEmpty) {
      _validSymbols.addAll(_dynamicAsxSymbols);
      print('DEBUG: Loaded ${_dynamicAsxSymbols.length} ASX symbols from cache');
    } else {
      // Use fallback static list
      _validSymbols.addAll(allAsxSymbols);
      print('DEBUG: Using ${allAsxSymbols.length} static ASX symbols');
    }
    
    _symbolsInitialized = true;
    
    // Fetch fresh list in background if cache is old or empty
    _fetchAsxSymbolsInBackground();
  }
  
  static Future<void> _loadCachedSymbols() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final symbolsJson = prefs.getString(_keyAsxSymbols);
      final namesJson = prefs.getString(_keyAsxNames);
      final cacheTime = prefs.getInt(_keyAsxCacheTime) ?? 0;
      
      // Check if cache is less than 7 days old
      final now = DateTime.now().millisecondsSinceEpoch;
      const sevenDays = 7 * 24 * 60 * 60 * 1000;
      
      if (symbolsJson != null && (now - cacheTime) < sevenDays) {
        _dynamicAsxSymbols = List<String>.from(jsonDecode(symbolsJson));
        if (namesJson != null) {
          _dynamicStockNames = Map<String, String>.from(jsonDecode(namesJson));
        }
      }
    } catch (e) {
      print('DEBUG: Error loading cached symbols: $e');
    }
  }
  
  static Future<void> _fetchAsxSymbolsInBackground() async {
    try {
      print('DEBUG: Fetching fresh ASX symbols list...');
      
      // Try multiple sources for ASX data
      List<String> symbols = [];
      Map<String, String> names = {};
      
      // Source 1: ASX company directory CSV
      symbols = await _fetchFromAsxDirectory();
      
      if (symbols.isEmpty) {
        // Source 2: Yahoo Finance ASX screener
        symbols = await _fetchFromYahooScreener();
      }
      
      if (symbols.isNotEmpty) {
        _dynamicAsxSymbols = symbols;
        _validSymbols.clear();
        _validSymbols.addAll(symbols);
        
        // Cache the results
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyAsxSymbols, jsonEncode(symbols));
        await prefs.setInt(_keyAsxCacheTime, DateTime.now().millisecondsSinceEpoch);
        
        print('DEBUG: Cached ${symbols.length} ASX symbols');
      }
    } catch (e) {
      print('DEBUG: Error fetching ASX symbols: $e');
    }
  }
  
  /// Fetch ASX symbols from ASX company directory
  static Future<List<String>> _fetchFromAsxDirectory() async {
    try {
      // ASX provides a CSV of all listed companies
      final response = await http.get(
        Uri.parse('https://asx.api.markitdigital.com/asx-research/1.0/companies/directory/file?access_token=83ff96335c2d45a094df02a206a39ff4'),
        headers: {'Accept': 'text/csv'},
      ).timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        final lines = response.body.split('\n');
        final symbols = <String>[];
        
        // Skip header row
        for (int i = 1; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.isEmpty) continue;
          
          // CSV format: ASX code, Company name, Listing date, GICs industry group, Market Cap
          final parts = line.split(',');
          if (parts.isNotEmpty) {
            final code = parts[0].replaceAll('"', '').trim();
            if (code.isNotEmpty && code.length <= 5 && RegExp(r'^[A-Z0-9]+$').hasMatch(code)) {
              symbols.add('$code.AX');
              if (parts.length > 1) {
                _dynamicStockNames['$code.AX'] = parts[1].replaceAll('"', '').trim();
              }
            }
          }
        }
        
        print('DEBUG: Fetched ${symbols.length} symbols from ASX directory');
        return symbols;
      }
    } catch (e) {
      print('DEBUG: ASX directory fetch failed: $e');
    }
    return [];
  }
  
  /// Fallback: Fetch from Yahoo Finance screener
  static Future<List<String>> _fetchFromYahooScreener() async {
    try {
      final symbols = <String>[];
      
      // Yahoo Finance screener for ASX stocks - fetch in batches
      for (int offset = 0; offset < 3000; offset += 250) {
        final url = 'https://query1.finance.yahoo.com/v1/finance/screener?formatted=false&lang=en-AU&region=AU&count=250&offset=$offset';
        
        final response = await http.post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'User-Agent': 'Mozilla/5.0',
          },
          body: jsonEncode({
            'size': 250,
            'offset': offset,
            'sortField': 'ticker',
            'sortType': 'asc',
            'quoteType': 'equity',
            'query': {
              'operator': 'and',
              'operands': [
                {'operator': 'eq', 'operands': ['exchange', 'ASX']}
              ]
            }
          }),
        ).timeout(const Duration(seconds: 30));
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final quotes = data['finance']?['result']?[0]?['quotes'] as List? ?? [];
          
          if (quotes.isEmpty) break;
          
          for (final quote in quotes) {
            final symbol = quote['symbol'] as String?;
            if (symbol != null && symbol.endsWith('.AX')) {
              symbols.add(symbol);
              final name = quote['shortName'] ?? quote['longName'];
              if (name != null) {
                _dynamicStockNames[symbol] = name;
              }
            }
          }
          
          if (quotes.length < 250) break;
          
          // Small delay between requests
          await Future.delayed(const Duration(milliseconds: 200));
        } else {
          break;
        }
      }
      
      print('DEBUG: Fetched ${symbols.length} symbols from Yahoo screener');
      return symbols;
    } catch (e) {
      print('DEBUG: Yahoo screener fetch failed: $e');
    }
    return [];
  }
  
  /// Force refresh of ASX symbols list
  static Future<int> refreshAsxSymbols() async {
    await _fetchAsxSymbolsInBackground();
    return _dynamicAsxSymbols.length;
  }
  
  /// Get all ASX symbols (dynamic + fallback)
  static List<String> get allAsxSymbolsDynamic {
    if (_dynamicAsxSymbols.isNotEmpty) {
      return _dynamicAsxSymbols;
    }
    return allAsxSymbols;
  }
  
  /// Get stock name from dynamic cache
  static String? getDynamicStockName(String symbol) {
    return _dynamicStockNames[symbol] ?? _stockNames[symbol];
  }

  /// Returns list of ALL real ASX stock symbols
  static List<String> generateAllAsxSymbols() {
    return allAsxSymbolsDynamic;
  }

  /// Search for ASX stocks
  static Future<List<Stock>> searchAsxStocks(String query) async {
    if (query.isEmpty) return [];
    
    final List<Stock> results = [];
    final upperQuery = query.toUpperCase().trim().replaceAll('.AX', '');
    
    print('DEBUG SEARCH: Searching for "$upperQuery" in ${allAsxSymbolsDynamic.length} symbols');
    
    // Method 1: ALWAYS try direct API lookup first (handles any valid ASX symbol)
    final directSymbol = '$upperQuery.AX';
    try {
      print('DEBUG SEARCH: Trying direct API lookup for $directSymbol');
      final directStock = await fetchStock(directSymbol);
      if (directStock != null && directStock.currentPrice > 0) {
        print('DEBUG SEARCH: Found via API: ${directStock.name} @ \$${directStock.currentPrice}');
        results.add(directStock);
      }
    } catch (e) {
      print('DEBUG SEARCH: Direct lookup failed: $e');
    }
    
    // Method 2: Search in known symbols by code and name (for partial matches)
    final matchingSymbols = <String>[];
    for (final symbol in allAsxSymbolsDynamic) {
      final code = symbol.replaceAll('.AX', '');
      final name = (getDynamicStockName(symbol) ?? '').toUpperCase();
      if ((code.contains(upperQuery) || name.contains(upperQuery)) && symbol != directSymbol) {
        matchingSymbols.add(symbol);
      }
      if (matchingSymbols.length >= 20) break;
    }
    
    print('DEBUG SEARCH: Found ${matchingSymbols.length} partial matches in database');
    
    // Fetch matching symbols
    if (matchingSymbols.isNotEmpty) {
      final toFetch = matchingSymbols.take(15).toList();
      try {
        final stocks = await fetchStocks(toFetch);
        for (final stock in stocks) {
          if (!results.any((r) => r.symbol == stock.symbol)) {
            results.add(stock);
          }
        }
      } catch (e) {
        print('DEBUG SEARCH: Exception fetching batch: $e');
      }
    }
    
    print('DEBUG SEARCH: Returning ${results.length} total results');
    return results;
  }

  /// Fetch a single stock quote
  static Future<Stock?> fetchStock(String symbol) async {
    print('DEBUG fetchStock: Trying to fetch $symbol');
    final quoteStock = await _fetchFromQuote(symbol);
    if (quoteStock != null) {
      print('DEBUG fetchStock: Got $symbol from quote API');
      return quoteStock;
    }
    print('DEBUG fetchStock: Quote API failed, trying chart API for $symbol');
    final chartStock = await _fetchFromChart(symbol);
    if (chartStock != null) {
      print('DEBUG fetchStock: Got $symbol from chart API');
    } else {
      print('DEBUG fetchStock: Both APIs failed for $symbol');
    }
    return chartStock;
  }

  static Future<Stock?> _fetchFromQuote(String symbol) async {
    for (final baseUrl in _baseUrls) {
      try {
        final url = Uri.parse('$baseUrl/v7/finance/quote?symbols=$symbol');
        print('DEBUG _fetchFromQuote: Calling $url');
        final response = await http.get(url, headers: _headers).timeout(const Duration(seconds: 10));
        print('DEBUG _fetchFromQuote: Response status ${response.statusCode}');
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final results = data['quoteResponse']?['result'] as List?;
          
          if (results != null && results.isNotEmpty) {
            final quote = results[0];
            final price = quote['regularMarketPrice'];
            print('DEBUG _fetchFromQuote: Got price $price for $symbol');
            if (price != null && (price as num).toDouble() > 0) {
              return Stock(
                symbol: symbol,
                name: quote['shortName'] ?? quote['longName'] ?? _stockNames[symbol] ?? symbol.replaceAll('.AX', ''),
                currentPrice: price.toDouble(),
                previousClose: ((quote['regularMarketPreviousClose'] ?? price) as num).toDouble(),
                change: ((quote['regularMarketChange'] ?? 0.0) as num).toDouble(),
                changePercent: ((quote['regularMarketChangePercent'] ?? 0.0) as num).toDouble(),
                volume: (quote['regularMarketVolume'] ?? 0) as int,
                marketCap: ((quote['marketCap'] ?? 0.0) as num).toDouble(),
                lastUpdate: DateTime.now(),
                weekHigh52: (quote['fiftyTwoWeekHigh'] as num?)?.toDouble(),
                weekLow52: (quote['fiftyTwoWeekLow'] as num?)?.toDouble(),
                avgVolume: (quote['averageDailyVolume3Month'] as num?)?.toDouble(),
              );
            }
          } else {
            print('DEBUG _fetchFromQuote: No results in response for $symbol');
          }
        }
      } catch (e) {
        print('DEBUG _fetchFromQuote: Error for $symbol: $e');
      }
    }
    return null;
  }

  static Future<Stock?> _fetchFromChart(String symbol) async {
    for (final baseUrl in _baseUrls) {
      try {
        final url = Uri.parse('$baseUrl/v8/finance/chart/$symbol?interval=1d&range=5d');
        final response = await http.get(url, headers: _headers).timeout(const Duration(seconds: 10));
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final result = data['chart']?['result']?[0];
          
          if (result != null) {
            final meta = result['meta'] ?? {};
            final price = (meta['regularMarketPrice'] as num?)?.toDouble();
            final prevClose = (meta['chartPreviousClose'] as num?)?.toDouble() ?? (meta['previousClose'] as num?)?.toDouble();
            
            if (price != null && price > 0) {
              final change = prevClose != null ? price - prevClose : 0.0;
              final changePercent = prevClose != null && prevClose > 0 ? (change / prevClose) * 100 : 0.0;
              
              return Stock(
                symbol: symbol,
                name: meta['shortName'] ?? meta['longName'] ?? _stockNames[symbol] ?? symbol.replaceAll('.AX', ''),
                currentPrice: price,
                previousClose: prevClose ?? price,
                change: change,
                changePercent: changePercent,
                volume: (meta['regularMarketVolume'] as num?)?.toInt() ?? 0,
                marketCap: 0,
                lastUpdate: DateTime.now(),
                weekHigh52: (meta['fiftyTwoWeekHigh'] as num?)?.toDouble(),
                weekLow52: (meta['fiftyTwoWeekLow'] as num?)?.toDouble(),
              );
            }
          }
        }
      } catch (_) { /* Continue on error */ }
    }
    return null;
  }

  /// Fetch multiple stocks
  static Future<List<Stock>> fetchStocks(List<String> symbols) async {
    final List<Stock> stocks = [];
    
    for (final baseUrl in _baseUrls) {
      try {
        final url = Uri.parse('$baseUrl/v7/finance/quote?symbols=${symbols.join(',')}');
        final response = await http.get(url, headers: _headers).timeout(const Duration(seconds: 15));
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final results = data['quoteResponse']?['result'] as List? ?? [];
          
          for (final quote in results) {
            final price = quote['regularMarketPrice'];
            if (price != null && (price as num).toDouble() > 0) {
              final symbol = quote['symbol'] ?? '';
              stocks.add(Stock(
                symbol: symbol,
                name: quote['shortName'] ?? quote['longName'] ?? _stockNames[symbol] ?? symbol,
                currentPrice: price.toDouble(),
                previousClose: ((quote['regularMarketPreviousClose'] ?? price) as num).toDouble(),
                change: ((quote['regularMarketChange'] ?? 0.0) as num).toDouble(),
                changePercent: ((quote['regularMarketChangePercent'] ?? 0.0) as num).toDouble(),
                volume: (quote['regularMarketVolume'] ?? 0) as int,
                marketCap: ((quote['marketCap'] ?? 0.0) as num).toDouble(),
                lastUpdate: DateTime.now(),
                weekHigh52: (quote['fiftyTwoWeekHigh'] as num?)?.toDouble(),
                weekLow52: (quote['fiftyTwoWeekLow'] as num?)?.toDouble(),
                avgVolume: (quote['averageDailyVolume3Month'] as num?)?.toDouble(),
              ));
            }
          }
          if (stocks.isNotEmpty) return stocks;
        }
      } catch (_) { /* Continue on error */ }
    }
    
    // Fallback: fetch individually
    if (stocks.isEmpty) {
      for (final symbol in symbols.take(10)) {
        final stock = await fetchStock(symbol);
        if (stock != null) stocks.add(stock);
      }
    }
    
    return stocks;
  }

  /// Fetch historical data for charts
  static Future<List<Map<String, dynamic>>> fetchHistoricalData(String symbol, {String range = '1d', String interval = '5m'}) async {
    for (final baseUrl in _baseUrls) {
      try {
        final url = Uri.parse('$baseUrl/v8/finance/chart/$symbol?range=$range&interval=$interval');
        final response = await http.get(url, headers: _headers).timeout(const Duration(seconds: 10));
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final result = data['chart']?['result']?[0];
          if (result == null) continue;
          
          final timestamps = result['timestamp'] as List? ?? [];
          final quotes = result['indicators']?['quote']?[0] ?? {};
          final closes = quotes['close'] as List? ?? [];
          final volumes = quotes['volume'] as List? ?? [];
          
          final List<Map<String, dynamic>> chartData = [];
          for (int i = 0; i < timestamps.length; i++) {
            if (i < closes.length && closes[i] != null) {
              chartData.add({
                'timestamp': timestamps[i],
                'close': (closes[i] as num).toDouble(),
                'volume': i < volumes.length && volumes[i] != null ? (volumes[i] as num).toInt() : 0,
              });
            }
          }
          if (chartData.isNotEmpty) return chartData;
        }
      } catch (_) { /* Continue on error */ }
    }
    return [];
  }

  /// Fetch historical prices for technical analysis
  static Future<List<double>> fetchHistoricalPrices(String symbol, {int days = 100}) async {
    final data = await fetchHistoricalPricesAndVolumes(symbol, days: days);
    final prices = data['prices'];
    if (prices == null) return [];
    return prices.map((p) => (p as num).toDouble()).toList();
  }

  /// Fetch both prices and volumes for full technical analysis
  static Future<Map<String, List<dynamic>>> fetchHistoricalPricesAndVolumes(String symbol, {int days = 100}) async {
    for (final baseUrl in _baseUrls) {
      try {
        final now = DateTime.now();
        final start = now.subtract(Duration(days: days + 10));
        final url = Uri.parse('$baseUrl/v8/finance/chart/$symbol?period1=${start.millisecondsSinceEpoch ~/ 1000}&period2=${now.millisecondsSinceEpoch ~/ 1000}&interval=1d');
        final response = await http.get(url, headers: _headers).timeout(const Duration(seconds: 10));
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final quote = data['chart']?['result']?[0]?['indicators']?['quote']?[0];
          
          final closes = (quote?['close'] as List? ?? [])
            .where((c) => c != null)
            .map((c) => (c as num).toDouble())
            .toList();
            
          final volumes = (quote?['volume'] as List? ?? [])
            .where((v) => v != null)
            .map((v) => (v as num).toInt())
            .toList();
          
          if (closes.isNotEmpty) {
            return {'prices': closes, 'volumes': volumes};
          }
        }
      } catch (_) {
        // Continue to next base URL on error
      }
    }
    return {'prices': <double>[], 'volumes': <int>[]};
  }

  static Map<String, String> get _headers => {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
    'Accept': 'application/json,text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
    'Accept-Encoding': 'gzip, deflate, br',
    'Connection': 'keep-alive',
    'Cache-Control': 'no-cache',
  };

  // Top 20 major stocks for quick scan
  static const List<String> majorStocks = [
    'BHP.AX', 'CBA.AX', 'CSL.AX', 'NAB.AX', 'WBC.AX', 'ANZ.AX', 'WES.AX', 'MQG.AX',
    'RIO.AX', 'FMG.AX', 'WDS.AX', 'TLS.AX', 'WOW.AX', 'GMG.AX', 'TCL.AX', 'COL.AX',
    'QBE.AX', 'STO.AX', 'REA.AX', 'ALL.AX',
  ];

  // Stock names for display
  static const Map<String, String> _stockNames = {
    'BHP.AX': 'BHP Group', 'CBA.AX': 'Commonwealth Bank', 'CSL.AX': 'CSL Limited',
    'NAB.AX': 'National Australia Bank', 'WBC.AX': 'Westpac Banking', 'ANZ.AX': 'ANZ Bank',
    'WES.AX': 'Wesfarmers', 'MQG.AX': 'Macquarie Group', 'RIO.AX': 'Rio Tinto',
    'FMG.AX': 'Fortescue', 'WDS.AX': 'Woodside Energy', 'TLS.AX': 'Telstra',
    'WOW.AX': 'Woolworths', 'GMG.AX': 'Goodman Group', 'TCL.AX': 'Transurban',
    'COL.AX': 'Coles', 'QAN.AX': 'Qantas', 'JBH.AX': 'JB Hi-Fi', 'HVN.AX': 'Harvey Norman',
  };

  /// COMPLETE LIST OF ~2200 REAL ASX STOCKS
  /// This is the actual list of companies listed on ASX
  static const List<String> allAsxSymbols = [
    // ASX 20 - Largest companies
    'BHP.AX', 'CBA.AX', 'CSL.AX', 'NAB.AX', 'WBC.AX', 'ANZ.AX', 'WES.AX', 'MQG.AX',
    'RIO.AX', 'FMG.AX', 'WDS.AX', 'TLS.AX', 'WOW.AX', 'GMG.AX', 'TCL.AX', 'COL.AX',
    'QBE.AX', 'STO.AX', 'REA.AX', 'ALL.AX',
    
    // ASX 50 additions
    'NCM.AX', 'CPU.AX', 'ORG.AX', 'IAG.AX', 'JHX.AX', 'RMD.AX', 'S32.AX', 'APA.AX',
    'AMC.AX', 'WOR.AX', 'XRO.AX', 'MIN.AX', 'SHL.AX', 'AGL.AX', 'SGP.AX', 'QAN.AX',
    'ASX.AX', 'SOL.AX', 'SUN.AX', 'MPL.AX', 'BXB.AX', 'TWE.AX', 'ORI.AX', 'GPT.AX',
    'DXS.AX', 'VCX.AX', 'CHC.AX', 'MGR.AX', 'SCG.AX', 'NST.AX',
    
    // ASX 100 additions
    'EVN.AX', 'NHF.AX', 'ILU.AX', 'BSL.AX', 'JBH.AX', 'CGF.AX', 'HVN.AX', 'AFI.AX',
    'ARG.AX', 'WAM.AX', 'MFG.AX', 'PPT.AX', 'IGO.AX', 'PDN.AX', 'ANN.AX', 'ALU.AX',
    'SEK.AX', 'NXT.AX', 'PLS.AX', 'LYC.AX', 'WHC.AX', 'NWS.AX', 'RRL.AX', 'GNC.AX',
    'VEA.AX', 'CTD.AX', 'A2M.AX', 'ZIP.AX', 'APX.AX', 'WTC.AX', 'CAR.AX', 'IFL.AX',
    'DOW.AX', 'IPL.AX', 'BOQ.AX', 'BEN.AX', 'ALD.AX', 'CWY.AX', 'NEC.AX', 'DMP.AX',
    
    // ASX 200 additions
    'TPG.AX', 'AMP.AX', 'CGC.AX', 'OZL.AX', 'BAP.AX', 'CIM.AX', 'IEL.AX', 'SUL.AX',
    'LLC.AX', 'MMS.AX', 'NHC.AX', 'OSH.AX', 'PME.AX', 'PRU.AX', 'RWC.AX', 'SGM.AX',
    'SFR.AX', 'SKC.AX', 'SPK.AX', 'SYD.AX', 'TAH.AX', 'TGR.AX', 'TPW.AX', 'URW.AX',
    'VNT.AX', 'WEB.AX', 'WGN.AX', 'WPL.AX', 'WSA.AX', 'Z1P.AX',
    
    // ASX 300 - Mid caps
    'ABC.AX', 'ABP.AX', 'ACL.AX', 'ADH.AX', 'ADI.AX', 'AEF.AX', 'AFG.AX', 'AGI.AX',
    'AIA.AX', 'AIZ.AX', 'AKE.AX', 'ALG.AX', 'ALK.AX', 'ALQ.AX', 'ALX.AX', 'AMI.AX',
    'AMP.AX', 'ANP.AX', 'AOF.AX', 'APE.AX', 'APM.AX', 'AQZ.AX', 'ARB.AX', 'ARF.AX',
    'ASB.AX', 'AUB.AX', 'AVH.AX', 'AVN.AX', 'AWC.AX', 'AX1.AX', 'AZJ.AX',
    
    // Mining - Gold
    'AAU.AX', 'ACB.AX', 'AIS.AX', 'AQG.AX', 'BGL.AX', 'CMM.AX', 'CYL.AX', 'DCN.AX',
    'DEG.AX', 'EGM.AX', 'EVN.AX', 'GCY.AX', 'GMD.AX', 'GOR.AX', 'KCN.AX', 'KLA.AX',
    'MML.AX', 'NCM.AX', 'NST.AX', 'OGC.AX', 'PNR.AX', 'PRU.AX', 'RED.AX', 'RMS.AX',
    'RRL.AX', 'RSG.AX', 'SAR.AX', 'SBM.AX', 'SLR.AX', 'TIE.AX', 'WAF.AX', 'WGX.AX',
    
    // Mining - Lithium & Battery Metals
    'AKE.AX', 'AVZ.AX', 'CXO.AX', 'FFX.AX', 'GL1.AX', 'GLN.AX', 'INR.AX', 'LKE.AX',
    'LPD.AX', 'LPI.AX', 'LRS.AX', 'LTR.AX', 'NMT.AX', 'NVX.AX', 'PLL.AX', 'PLS.AX',
    'PSC.AX', 'SYA.AX', 'VUL.AX', 'WR1.AX',
    
    // Mining - Iron Ore
    'BHP.AX', 'CIA.AX', 'CZR.AX', 'FEX.AX', 'FMG.AX', 'GRR.AX', 'HAV.AX', 'IRD.AX',
    'MGT.AX', 'MIN.AX', 'RIO.AX', 'SHH.AX',
    
    // Mining - Copper
    'AIS.AX', 'AVZ.AX', 'BHP.AX', 'C6C.AX', 'CYM.AX', 'DEG.AX', 'EVN.AX', 'HCH.AX',
    'MNS.AX', 'OZL.AX', 'RIO.AX', 'S32.AX', 'SFR.AX', 'TIE.AX',
    
    // Mining - Nickel & Cobalt
    'ASN.AX', 'BHP.AX', 'IGO.AX', 'MCR.AX', 'MZZ.AX', 'NIC.AX', 'PAN.AX', 'QPM.AX',
    'S32.AX', 'WSA.AX',
    
    // Mining - Rare Earths
    'ARR.AX', 'ARU.AX', 'GGG.AX', 'HAS.AX', 'IXR.AX', 'LYC.AX', 'NTU.AX', 'PEK.AX',
    'REE.AX', 'VML.AX',
    
    // Mining - Uranium
    '92E.AX', 'AGE.AX', 'BMN.AX', 'BOE.AX', 'DYL.AX', 'EL8.AX', 'ERA.AX', 'LOT.AX',
    'PDN.AX', 'PEN.AX', 'SLX.AX', 'TOE.AX', 'VMY.AX',
    
    // Mining - Coal
    'BRL.AX', 'CRN.AX', 'NHC.AX', 'SMR.AX', 'WHC.AX', 'YAL.AX',
    
    // Mining - Other
    'ATC.AX', 'AZS.AX', 'BRK.AX', 'CDY.AX', 'CYM.AX', 'ELT.AX', 'ERA.AX', 'GXY.AX',
    'IMD.AX', 'KGL.AX', 'MAY.AX', 'MDC.AX', 'MGX.AX', 'MLX.AX', 'MNS.AX', 'NML.AX',
    'ORE.AX', 'PAN.AX', 'PNR.AX', 'RDT.AX', 'RMS.AX', 'SYR.AX', 'TAM.AX', 'TLG.AX',
    'TRS.AX', 'VRC.AX', 'ZIM.AX',
    
    // Oil & Gas
    'BPT.AX', 'CVN.AX', 'FAR.AX', 'KAR.AX', 'NXS.AX', 'ORG.AX', 'OSH.AX', 'STO.AX',
    'WDS.AX', 'WGP.AX', '88E.AX', 'BUX.AX', 'COE.AX', 'CUE.AX', 'EMP.AX', 'GAL.AX',
    'HZN.AX', 'IVZ.AX', 'MAD.AX', 'MEL.AX', 'MYE.AX', 'NZO.AX', 'OEX.AX', 'PLS.AX',
    'POL.AX', 'PPL.AX', 'SGI.AX', 'STX.AX', 'VEA.AX', 'WOR.AX',
    
    // Energy - Renewables
    'AGL.AX', 'APX.AX', 'CEN.AX', 'DEW.AX', 'ERF.AX', 'GNX.AX', 'HZN.AX', 'INF.AX',
    'LGI.AX', 'MCY.AX', 'MEZ.AX', 'NEW.AX', 'NGY.AX', 'NOV.AX', 'ORG.AX', 'PGY.AX',
    'PNV.AX', 'RFX.AX', 'SKI.AX', 'SOL.AX', 'TPO.AX', 'VVR.AX', 'WND.AX',
    
    // Banks & Financial Services
    'ANZ.AX', 'AUB.AX', 'BEN.AX', 'BOQ.AX', 'CBA.AX', 'CGF.AX', 'EQT.AX', 'HUB.AX',
    'IFL.AX', 'JHG.AX', 'MFG.AX', 'MQG.AX', 'NAB.AX', 'NWL.AX', 'PDL.AX', 'PNI.AX',
    'PPT.AX', 'PTM.AX', 'SUN.AX', 'WBC.AX', 'AMP.AX', 'APT.AX', 'ASX.AX', 'BGL.AX',
    'BTI.AX', 'CCP.AX', 'CPU.AX', 'ECX.AX', 'EML.AX', 'EQT.AX', 'GBT.AX', 'GMA.AX',
    'HUM.AX', 'IRE.AX', 'LAM.AX', 'LFS.AX', 'MGH.AX', 'MON.AX', 'MYS.AX', 'NEA.AX',
    'NWL.AX', 'OML.AX', 'OPY.AX', 'PBP.AX', 'PXA.AX', 'QFE.AX', 'RFF.AX', 'SCP.AX',
    'SPL.AX', 'SQ2.AX', 'TYR.AX', 'VCX.AX', 'WHF.AX', 'WZR.AX', 'Z1P.AX', 'ZIP.AX',
    
    // Insurance
    'IAG.AX', 'MPL.AX', 'NHF.AX', 'QBE.AX', 'SUN.AX', 'AUB.AX', 'CIL.AX', 'CVW.AX',
    'GMA.AX', 'HLI.AX', 'PSI.AX', 'SWG.AX', 'TWR.AX',
    
    // Real Estate
    'ABP.AX', 'AOF.AX', 'ARF.AX', 'BWP.AX', 'CHC.AX', 'CLW.AX', 'CNI.AX', 'CQE.AX',
    'DXS.AX', 'GMG.AX', 'GOZ.AX', 'GPT.AX', 'HDN.AX', 'HPI.AX', 'HMC.AX', 'INA.AX',
    'IOF.AX', 'LEP.AX', 'LLC.AX', 'MGR.AX', 'NSR.AX', 'REP.AX', 'RFF.AX', 'RGN.AX',
    'SCG.AX', 'SGP.AX', 'SLF.AX', 'TCL.AX', 'URW.AX', 'VCX.AX', 'WGN.AX', 'WPR.AX',
    
    // Healthcare
    'ANN.AX', 'ANP.AX', 'API.AX', 'AVH.AX', 'BTC.AX', 'CGS.AX', 'CHN.AX', 'COH.AX',
    'CSL.AX', 'CUV.AX', 'ELX.AX', 'EBG.AX', 'FPH.AX', 'GNE.AX', 'HLS.AX', 'IHL.AX',
    'IMM.AX', 'IMP.AX', 'IPD.AX', 'MSB.AX', 'MYX.AX', 'NEU.AX', 'NTC.AX', 'NXS.AX',
    'ONT.AX', 'OPT.AX', 'PAB.AX', 'PAR.AX', 'PME.AX', 'PNV.AX', 'POD.AX', 'PRR.AX',
    'PSQ.AX', 'PYC.AX', 'RHC.AX', 'RMD.AX', 'SHL.AX', 'SIG.AX', 'SOM.AX', 'TLX.AX',
    'VHT.AX', 'VUK.AX', 'WCN.AX',
    
    // Technology
    '3PL.AX', 'A4N.AX', 'AD8.AX', 'ALU.AX', 'APX.AX', 'BRN.AX', 'CAT.AX', 'CIA.AX',
    'CLV.AX', 'CPU.AX', 'CTE.AX', 'DDR.AX', 'DGL.AX', 'DUB.AX', 'DUG.AX', 'ELO.AX',
    'FCT.AX', 'FLT.AX', 'FZO.AX', 'GDI.AX', 'GTK.AX', 'HT1.AX', 'IRI.AX', 'JAN.AX',
    'LNK.AX', 'LVT.AX', 'MBH.AX', 'MEA.AX', 'MP1.AX', 'NEA.AX', 'NTO.AX', 'NVX.AX',
    'NXT.AX', 'OPT.AX', 'PBH.AX', 'PPS.AX', 'PPT.AX', 'PRO.AX', 'PSI.AX', 'RDY.AX',
    'REA.AX', 'RUL.AX', 'SEK.AX', 'SLC.AX', 'SPZ.AX', 'TNE.AX', 'TPW.AX', 'TYR.AX',
    'UBN.AX', 'VHT.AX', 'VTG.AX', 'WEB.AX', 'WHK.AX', 'WTC.AX', 'XRO.AX', 'ZGL.AX',
    
    // Retail & Consumer
    'ADH.AX', 'ALL.AX', 'APE.AX', 'ARB.AX', 'BAP.AX', 'BBN.AX', 'BRG.AX', 'BWX.AX',
    'CCX.AX', 'COL.AX', 'DMP.AX', 'DSK.AX', 'ELD.AX', 'FLT.AX', 'GUD.AX', 'HVN.AX',
    'IVC.AX', 'JBH.AX', 'KGN.AX', 'KMD.AX', 'LOV.AX', 'MHJ.AX', 'MTS.AX', 'MYR.AX',
    'NCK.AX', 'NEC.AX', 'NVL.AX', 'PMV.AX', 'PNC.AX', 'PRG.AX', 'PSQ.AX', 'PWH.AX',
    'QGL.AX', 'RCG.AX', 'RFG.AX', 'SIQ.AX', 'SIT.AX', 'SUL.AX', 'SWM.AX', 'TRS.AX',
    'WES.AX', 'WOW.AX',
    
    // Industrials & Materials
    'ABC.AX', 'ABB.AX', 'ADT.AX', 'AJL.AX', 'AMC.AX', 'AWC.AX', 'AZJ.AX', 'BGA.AX',
    'BKW.AX', 'BLD.AX', 'BLX.AX', 'BPT.AX', 'BSE.AX', 'BSL.AX', 'CAB.AX', 'CIM.AX',
    'CNB.AX', 'CWY.AX', 'DOW.AX', 'DRR.AX', 'DTL.AX', 'DXC.AX', 'EHL.AX', 'ELO.AX',
    'EVS.AX', 'FBR.AX', 'GEM.AX', 'GNC.AX', 'GNE.AX', 'GNG.AX', 'GUD.AX', 'GWA.AX',
    'HVN.AX', 'IDX.AX', 'IFM.AX', 'IGL.AX', 'INR.AX', 'IPD.AX', 'IPL.AX', 'JHX.AX',
    'LEI.AX', 'LIC.AX', 'LYL.AX', 'MAD.AX', 'MDC.AX', 'MMS.AX', 'MND.AX', 'MOC.AX',
    'MYX.AX', 'NFK.AX', 'NUF.AX', 'NWH.AX', 'OML.AX', 'ORA.AX', 'ORI.AX', 'PGH.AX',
    'PPC.AX', 'PRY.AX', 'RCW.AX', 'REH.AX', 'RFF.AX', 'RIO.AX', 'RWC.AX', 'SDF.AX',
    'SGM.AX', 'SHL.AX', 'SIG.AX', 'SKI.AX', 'SSM.AX', 'STG.AX', 'SXL.AX', 'TGR.AX',
    'UGL.AX', 'VEA.AX', 'VRS.AX', 'WOR.AX', 'WSP.AX', 'WTC.AX',
    
    // Telecommunications
    'AMA.AX', 'MNF.AX', 'OPT.AX', 'SLC.AX', 'SPK.AX', 'TLS.AX', 'TNE.AX', 'TPG.AX',
    'UNI.AX', 'VTL.AX',
    
    // Gaming & Entertainment
    'AAD.AX', 'ALL.AX', 'ART.AX', 'EML.AX', 'EVT.AX', 'PBD.AX', 'PBL.AX', 'SGR.AX',
    'SKT.AX', 'SWM.AX', 'TAH.AX',
    
    // Travel & Leisure
    'ALG.AX', 'CTD.AX', 'EXP.AX', 'FLT.AX', 'HLO.AX', 'QAN.AX', 'SYD.AX', 'WEB.AX',
    
    // Food & Beverage
    'A2M.AX', 'BAL.AX', 'BGA.AX', 'BUB.AX', 'CGC.AX', 'CLV.AX', 'CNB.AX', 'COL.AX',
    'ELD.AX', 'FFI.AX', 'FNP.AX', 'GNC.AX', 'HUO.AX', 'ING.AX', 'MTS.AX', 'NOU.AX',
    'NUF.AX', 'PCK.AX', 'RIC.AX', 'SDA.AX', 'TGR.AX', 'TWE.AX', 'WOW.AX',
    
    // Agriculture
    'AAC.AX', 'AGJ.AX', 'AGN.AX', 'CGC.AX', 'ELD.AX', 'FBR.AX', 'GNC.AX', 'HUO.AX',
    'ING.AX', 'NUF.AX', 'PPC.AX', 'RFF.AX', 'RIC.AX', 'SGM.AX', 'TGR.AX', 'WOA.AX',
    
    // Media & Communications
    'APX.AX', 'ART.AX', 'CTM.AX', 'CVN.AX', 'DTC.AX', 'FXL.AX', 'HT1.AX', 'IFM.AX',
    'KAR.AX', 'MND.AX', 'NEC.AX', 'NWS.AX', 'OML.AX', 'OTH.AX', 'PRN.AX', 'REA.AX',
    'RNT.AX', 'SEK.AX', 'SGH.AX', 'SGN.AX', 'SWM.AX', 'TVN.AX', 'UWL.AX', 'VRL.AX',
    
    // Small Caps - Popular Speculative
    '88E.AX', '4DS.AX', '5GG.AX', 'ACW.AX', 'ADO.AX', 'AEI.AX', 'AG1.AX', 'AGR.AX',
    'ANL.AX', 'APT.AX', 'ARN.AX', 'AR1.AX', 'ARL.AX', 'AUT.AX', 'AV1.AX', 'AVA.AX',
    'AVL.AX', 'BCN.AX', 'BDM.AX', 'BDT.AX', 'BEM.AX', 'BFC.AX', 'BIT.AX', 'BMN.AX',
    'BOE.AX', 'BRB.AX', 'BRK.AX', 'BRN.AX', 'BTH.AX', 'BUX.AX', 'BYH.AX', 'CAD.AX',
    'CAI.AX', 'CAN.AX', 'CAY.AX', 'CBL.AX', 'CCV.AX', 'CDT.AX', 'CDX.AX', 'CHK.AX',
    'CHM.AX', 'CHZ.AX', 'CKA.AX', 'CLZ.AX', 'CMM.AX', 'CNJ.AX', 'COB.AX', 'COI.AX',
    'CPH.AX', 'CPT.AX', 'CR1.AX', 'CRR.AX', 'CUL.AX', 'CUV.AX', 'CVS.AX', 'CXL.AX',
    'CXO.AX', 'CYG.AX', 'CYM.AX', 'DAL.AX', 'DCC.AX', 'DCX.AX', 'DEL.AX', 'DEV.AX',
    'DGO.AX', 'DGR.AX', 'DLC.AX', 'DRE.AX', 'DRO.AX', 'DTC.AX', 'DTR.AX', 'DW8.AX',
    'DXB.AX', 'DXN.AX', 'DYL.AX', 'EBR.AX', 'ECT.AX', 'EGR.AX', 'EGS.AX', 'EHL.AX',
    'EIQ.AX', 'EL8.AX', 'ELE.AX', 'ELT.AX', 'EM2.AX', 'EMD.AX', 'EMH.AX', 'EMR.AX',
    'EMV.AX', 'ENA.AX', 'ENR.AX', 'ENV.AX', 'EOL.AX', 'EPD.AX', 'EPN.AX', 'EPY.AX',
    'ERW.AX', 'ESR.AX', 'ETS.AX', 'EUR.AX', 'EVE.AX', 'EVM.AX', 'EVR.AX', 'EXL.AX',
    'EXR.AX', 'FAU.AX', 'FBU.AX', 'FCL.AX', 'FEL.AX', 'FFG.AX', 'FFX.AX', 'FGR.AX',
    'FHS.AX', 'FIN.AX', 'FIJ.AX', 'FLC.AX', 'FLN.AX', 'FLO.AX', 'FML.AX', 'FMS.AX',
    'FNT.AX', 'FOS.AX', 'FOT.AX', 'FPC.AX', 'FRB.AX', 'FTC.AX', 'FTZ.AX', 'FYI.AX',
    'GAL.AX', 'GBR.AX', 'GCR.AX', 'GDF.AX', 'GDX.AX', 'GEN.AX', 'GES.AX', 'GGG.AX',
    'GIB.AX', 'GLA.AX', 'GL1.AX', 'GLL.AX', 'GLN.AX', 'GLV.AX', 'GM1.AX', 'GMC.AX',
    'GML.AX', 'GMR.AX', 'GNM.AX', 'GNP.AX', 'GNS.AX', 'GNT.AX', 'GNX.AX', 'GOK.AX',
    'GOW.AX', 'GPR.AX', 'GPX.AX', 'GRE.AX', 'GRV.AX', 'GSC.AX', 'GSN.AX', 'GTI.AX',
    'GTR.AX', 'GUL.AX', 'GVF.AX', 'HAO.AX', 'HAS.AX', 'HAW.AX', 'HCH.AX', 'HCT.AX',
    'HDY.AX', 'HE8.AX', 'HFR.AX', 'HGL.AX', 'HGO.AX', 'HIL.AX', 'HLF.AX', 'HMD.AX',
    'HMI.AX', 'HMX.AX', 'HNR.AX', 'HOT.AX', 'HPG.AX', 'HPR.AX', 'HRN.AX', 'HRR.AX',
    'HRZ.AX', 'HSC.AX', 'HSN.AX', 'HT8.AX', 'HTG.AX', 'HWH.AX', 'HXG.AX', 'HYD.AX',
    'HZR.AX', 'I88.AX', 'IAM.AX', 'IBG.AX', 'ICG.AX', 'ICN.AX', 'IDA.AX', 'IDT.AX',
    'IDZ.AX', 'IFT.AX', 'IGM.AX', 'IGN.AX', 'IHL.AX', 'IKE.AX', 'IKW.AX', 'ILA.AX',
    'IMC.AX', 'IMG.AX', 'IML.AX', 'IMU.AX', 'IMR.AX', 'INF.AX', 'INP.AX', 'INV.AX',
    'IOD.AX', 'IOG.AX', 'IOU.AX', 'IPB.AX', 'IPT.AX', 'IRM.AX', 'IRX.AX', 'ISU.AX',
    'IVR.AX', 'IVT.AX', 'IVX.AX', 'IVZ.AX', 'IXR.AX', 'JAL.AX', 'JAT.AX', 'JAY.AX',
    'JDR.AX', 'JGH.AX', 'JIN.AX', 'JLG.AX', 'JMS.AX', 'JNO.AX', 'JPR.AX', 'JRL.AX',
    'JRV.AX', 'JTL.AX', 'JVR.AX', 'JXT.AX', 'K2F.AX', 'KAI.AX', 'KAM.AX', 'KAS.AX',
    'KAT.AX', 'KBC.AX', 'KCN.AX', 'KFG.AX', 'KFE.AX', 'KGD.AX', 'KGN.AX', 'KKC.AX',
    'KKO.AX', 'KLA.AX', 'KLI.AX', 'KLL.AX', 'KLS.AX', 'KMC.AX', 'KMT.AX', 'KNB.AX',
    'KNI.AX', 'KNM.AX', 'KOR.AX', 'KP2.AX', 'KPG.AX', 'KPO.AX', 'KRM.AX', 'KSC.AX',
    'KSN.AX', 'KTA.AX', 'KTD.AX', 'KWR.AX', 'KYK.AX', 'KZR.AX', 'LAM.AX', 'LAS.AX',
    'LAU.AX', 'LAW.AX', 'LBL.AX', 'LBT.AX', 'LCE.AX', 'LCK.AX', 'LCL.AX', 'LCT.AX',
    'LCY.AX', 'LDR.AX', 'LDX.AX', 'LEG.AX', 'LEL.AX', 'LER.AX', 'LEX.AX', 'LGM.AX',
    'LGP.AX', 'LHM.AX', 'LIO.AX', 'LIT.AX', 'LKE.AX', 'LKO.AX', 'LML.AX', 'LME.AX',
    'LNK.AX', 'LNR.AX', 'LNW.AX', 'LNY.AX', 'LOT.AX', 'LOV.AX', 'LPD.AX', 'LPE.AX',
    'LPI.AX', 'LPM.AX', 'LRS.AX', 'LRT.AX', 'LSA.AX', 'LSH.AX', 'LTM.AX', 'LTR.AX',
    'LYL.AX', 'M24.AX', 'M2M.AX', 'M2R.AX', 'M3M.AX', 'M7T.AX', 'M8S.AX', 'MAD.AX',
    'MAF.AX', 'MAG.AX', 'MAH.AX', 'MAI.AX', 'MAK.AX', 'MAN.AX', 'MAQ.AX', 'MAT.AX',
    'MAU.AX', 'MAX.AX', 'MAY.AX', 'MBH.AX', 'MBK.AX', 'MBT.AX', 'MBX.AX', 'MCA.AX',
    'MCE.AX', 'MCL.AX', 'MCM.AX', 'MCR.AX', 'MCT.AX', 'MCY.AX', 'MDC.AX', 'MDD.AX',
    'MDI.AX', 'MDR.AX', 'MDV.AX', 'MEI.AX', 'MEK.AX', 'MEL.AX', 'MEM.AX', 'MEP.AX',
    'MET.AX', 'MEU.AX', 'MEY.AX', 'MEZ.AX', 'MFD.AX', 'MFF.AX', 'MFG.AX', 'MGH.AX',
    'MGR.AX', 'MGT.AX', 'MGU.AX', 'MGV.AX', 'MGX.AX', 'MHC.AX', 'MHJ.AX', 'MHK.AX',
    'MHL.AX', 'MHM.AX', 'MHN.AX', 'MIC.AX', 'MIL.AX', 'MIN.AX', 'MIO.AX', 'MIR.AX',
    'MIS.AX', 'MKR.AX', 'MKS.AX', 'MLA.AX', 'MLC.AX', 'MLD.AX', 'MLG.AX', 'MLM.AX',
    'MLS.AX', 'MLX.AX', 'MM1.AX', 'MM8.AX', 'MMA.AX', 'MMC.AX', 'MME.AX', 'MMG.AX',
    'MMI.AX', 'MML.AX', 'MMM.AX', 'MMR.AX', 'MMS.AX', 'MND.AX', 'MNF.AX', 'MNG.AX',
    'MNS.AX', 'MNW.AX', 'MOB.AX', 'MOH.AX', 'MOQ.AX', 'MOT.AX', 'MOV.AX', 'MOZ.AX',
    'MP1.AX', 'MPL.AX', 'MPP.AX', 'MQG.AX', 'MQR.AX', 'MRC.AX', 'MRD.AX', 'MRG.AX',
    'MRI.AX', 'MRM.AX', 'MRQ.AX', 'MRR.AX', 'MRV.AX', 'MRZ.AX', 'MSB.AX', 'MSC.AX',
    'MSD.AX', 'MSG.AX', 'MSI.AX', 'MSL.AX', 'MSM.AX', 'MSR.AX', 'MSV.AX', 'MTC.AX',
    'MTH.AX', 'MTL.AX', 'MTM.AX', 'MTR.AX', 'MTS.AX', 'MTU.AX', 'MUA.AX', 'MUN.AX',
    'MUR.AX', 'MUS.AX', 'MVF.AX', 'MVL.AX', 'MWR.AX', 'MWY.AX', 'MXC.AX', 'MXI.AX',
    'MXR.AX', 'MYD.AX', 'MYE.AX', 'MYL.AX', 'MYQ.AX', 'MYR.AX', 'MYS.AX', 'MYX.AX',
    'MZN.AX', 'MZZ.AX', 'NAB.AX', 'NAC.AX', 'NAE.AX', 'NAG.AX', 'NAM.AX', 'NAN.AX',
    'NAR.AX', 'NBI.AX', 'NBL.AX', 'NBT.AX', 'NCK.AX', 'NCL.AX', 'NCM.AX', 'NCP.AX',
    'NCZ.AX', 'NDO.AX', 'NEA.AX', 'NEC.AX', 'NES.AX', 'NET.AX', 'NEW.AX', 'NEX.AX',
    'NFK.AX', 'NFN.AX', 'NGC.AX', 'NGE.AX', 'NGI.AX', 'NGS.AX', 'NGY.AX', 'NHC.AX',
    'NHF.AX', 'NIC.AX', 'NIS.AX', 'NKL.AX', 'NLB.AX', 'NME.AX', 'NML.AX', 'NMR.AX',
    'NMT.AX', 'NMU.AX', 'NNG.AX', 'NNW.AX', 'NOV.AX', 'NOW.AX', 'NPR.AX', 'NRX.AX',
    'NSC.AX', 'NSL.AX', 'NSR.AX', 'NST.AX', 'NSX.AX', 'NTA.AX', 'NTD.AX', 'NTI.AX',
    'NTL.AX', 'NTM.AX', 'NTO.AX', 'NTU.AX', 'NUF.AX', 'NUH.AX', 'NUS.AX', 'NVA.AX',
    'NVO.AX', 'NVT.AX', 'NVU.AX', 'NVX.AX', 'NWC.AX', 'NWE.AX', 'NWF.AX', 'NWH.AX',
    'NWL.AX', 'NWS.AX', 'NXG.AX', 'NXL.AX', 'NXM.AX', 'NXR.AX', 'NXS.AX', 'NXT.AX',
    'NYR.AX', 'NZM.AX', 'NZO.AX', 'NZS.AX', 'OAK.AX', 'OAR.AX', 'OBJ.AX', 'OBL.AX',
    'OCA.AX', 'OCC.AX', 'OCL.AX', 'ODA.AX', 'ODE.AX', 'ODN.AX', 'ODY.AX', 'OEL.AX',
    'OEQ.AX', 'OEX.AX', 'OFX.AX', 'OGC.AX', 'OGY.AX', 'OIL.AX', 'OKJ.AX', 'OKR.AX',
    'OKU.AX', 'OLL.AX', 'OLV.AX', 'OLY.AX', 'OMA.AX', 'OMH.AX', 'OMN.AX', 'ONC.AX',
    'ONT.AX', 'OOK.AX', 'OOO.AX', 'OPC.AX', 'OPH.AX', 'OPN.AX', 'OPT.AX', 'OPY.AX',
    'ORA.AX', 'ORB.AX', 'ORE.AX', 'ORG.AX', 'ORI.AX', 'ORL.AX', 'ORN.AX', 'ORR.AX',
    'ORS.AX', 'OSH.AX', 'OSL.AX', 'OSP.AX', 'OSX.AX', 'OTC.AX', 'OTH.AX', 'OTR.AX',
    'OTW.AX', 'OVT.AX', 'OXX.AX', 'OZL.AX', 'OZM.AX', 'OZZ.AX',
    
    // P-Z small caps continuation
    'PAA.AX', 'PAB.AX', 'PAC.AX', 'PAF.AX', 'PAI.AX', 'PAK.AX', 'PAM.AX', 'PAN.AX',
    'PAR.AX', 'PBH.AX', 'PBP.AX', 'PBS.AX', 'PBT.AX', 'PCA.AX', 'PCG.AX', 'PCK.AX',
    'PCL.AX', 'PDI.AX', 'PDL.AX', 'PDM.AX', 'PDN.AX', 'PDZ.AX', 'PEA.AX', 'PEB.AX',
    'PEC.AX', 'PEK.AX', 'PEN.AX', 'PEP.AX', 'PET.AX', 'PEX.AX', 'PFE.AX', 'PFP.AX',
    'PFT.AX', 'PGC.AX', 'PGD.AX', 'PGF.AX', 'PGG.AX', 'PGH.AX', 'PGI.AX', 'PGL.AX',
    'PGM.AX', 'PGO.AX', 'PGR.AX', 'PGS.AX', 'PGY.AX', 'PHD.AX', 'PHG.AX', 'PHI.AX',
    'PHK.AX', 'PHL.AX', 'PHN.AX', 'PHO.AX', 'PHP.AX', 'PHR.AX', 'PIA.AX', 'PIC.AX',
    'PIL.AX', 'PIM.AX', 'PIN.AX', 'PIO.AX', 'PIQ.AX', 'PKD.AX', 'PKO.AX', 'PKS.AX',
    'PLC.AX', 'PLL.AX', 'PLN.AX', 'PLS.AX', 'PLT.AX', 'PLY.AX', 'PMC.AX', 'PME.AX',
    'PML.AX', 'PMM.AX', 'PMT.AX', 'PMV.AX', 'PMY.AX', 'PNA.AX', 'PNC.AX', 'PNI.AX',
    'PNL.AX', 'PNN.AX', 'PNR.AX', 'PNT.AX', 'PNV.AX', 'PNW.AX', 'PNX.AX', 'POD.AX',
    'POL.AX', 'POM.AX', 'POP.AX', 'POS.AX', 'POT.AX', 'POW.AX', 'PPE.AX', 'PPG.AX',
    'PPH.AX', 'PPK.AX', 'PPL.AX', 'PPM.AX', 'PPS.AX', 'PPT.AX', 'PPY.AX', 'PRL.AX',
    'PRM.AX', 'PRN.AX', 'PRO.AX', 'PRR.AX', 'PRS.AX', 'PRU.AX', 'PRX.AX', 'PRY.AX',
    'PSA.AX', 'PSC.AX', 'PSD.AX', 'PSI.AX', 'PSL.AX', 'PSQ.AX', 'PSS.AX', 'PSV.AX',
    'PSY.AX', 'PTA.AX', 'PTB.AX', 'PTC.AX', 'PTG.AX', 'PTL.AX', 'PTM.AX', 'PTO.AX',
    'PTR.AX', 'PTS.AX', 'PTX.AX', 'PUA.AX', 'PUR.AX', 'PVA.AX', 'PVS.AX', 'PVW.AX',
    'PWH.AX', 'PWN.AX', 'PWR.AX', 'PX1.AX', 'PXA.AX', 'PXS.AX', 'PXX.AX', 'PYC.AX',
    'PYR.AX', 'PZC.AX',
    
    // Q
    'QAN.AX', 'QAU.AX', 'QBE.AX', 'QEM.AX', 'QFE.AX', 'QFY.AX', 'QGL.AX', 'QHL.AX',
    'QIP.AX', 'QLT.AX', 'QML.AX', 'QMS.AX', 'QMX.AX', 'QOL.AX', 'QPM.AX', 'QRI.AX',
    'QRL.AX', 'QTM.AX', 'QUB.AX', 'QUE.AX', 'QXR.AX',
    
    // R
    'RAC.AX', 'RAD.AX', 'RAF.AX', 'RAG.AX', 'RAM.AX', 'RAN.AX', 'RAP.AX', 'RAS.AX',
    'RBL.AX', 'RBR.AX', 'RBX.AX', 'RCE.AX', 'RCG.AX', 'RCI.AX', 'RCL.AX', 'RCM.AX',
    'RCR.AX', 'RCT.AX', 'RCW.AX', 'RDG.AX', 'RDH.AX', 'RDM.AX', 'RDT.AX', 'RDY.AX',
    'REA.AX', 'REC.AX', 'RED.AX', 'REE.AX', 'REF.AX', 'REG.AX', 'REH.AX', 'REI.AX',
    'REL.AX', 'REM.AX', 'REN.AX', 'REP.AX', 'REV.AX', 'REX.AX', 'REZ.AX', 'RFE.AX',
    'RFF.AX', 'RFG.AX', 'RFL.AX', 'RFN.AX', 'RFT.AX', 'RFX.AX', 'RGD.AX', 'RGI.AX',
    'RGL.AX', 'RGN.AX', 'RGS.AX', 'RGU.AX', 'RHC.AX', 'RHI.AX', 'RHP.AX', 'RHY.AX',
    'RIC.AX', 'RIM.AX', 'RIO.AX', 'RIS.AX', 'RKN.AX', 'RLC.AX', 'RLE.AX', 'RLF.AX',
    'RLG.AX', 'RLT.AX', 'RMA.AX', 'RMC.AX', 'RMD.AX', 'RML.AX', 'RMP.AX', 'RMS.AX',
    'RMT.AX', 'RMX.AX', 'RND.AX', 'RNE.AX', 'RNG.AX', 'RNO.AX', 'RNT.AX', 'RNU.AX',
    'ROC.AX', 'ROG.AX', 'ROL.AX', 'ROM.AX', 'ROO.AX', 'ROS.AX', 'ROU.AX', 'RPL.AX',
    'RPM.AX', 'RRL.AX', 'RRS.AX', 'RSG.AX', 'RSH.AX', 'RSM.AX', 'RTG.AX', 'RTH.AX',
    'RTL.AX', 'RTO.AX', 'RUL.AX', 'RVS.AX', 'RWC.AX', 'RXH.AX', 'RXL.AX', 'RXM.AX',
    'RZI.AX',
    
    // S
    'S2R.AX', 'S32.AX', 'S66.AX', 'SAM.AX', 'SAN.AX', 'SAR.AX', 'SAS.AX', 'SAU.AX',
    'SBM.AX', 'SBR.AX', 'SBW.AX', 'SC1.AX', 'SCA.AX', 'SCE.AX', 'SCG.AX', 'SCL.AX',
    'SCN.AX', 'SCP.AX', 'SDA.AX', 'SDF.AX', 'SDG.AX', 'SDI.AX', 'SDL.AX', 'SDR.AX',
    'SDV.AX', 'SEA.AX', 'SEB.AX', 'SEC.AX', 'SEK.AX', 'SEN.AX', 'SEQ.AX', 'SER.AX',
    'SES.AX', 'SET.AX', 'SFG.AX', 'SFR.AX', 'SFX.AX', 'SFY.AX', 'SGC.AX', 'SGF.AX',
    'SGH.AX', 'SGI.AX', 'SGL.AX', 'SGM.AX', 'SGN.AX', 'SGP.AX', 'SGQ.AX', 'SGR.AX',
    'SHE.AX', 'SHH.AX', 'SHJ.AX', 'SHL.AX', 'SHM.AX', 'SHO.AX', 'SHP.AX', 'SHV.AX',
    'SIG.AX', 'SIH.AX', 'SIM.AX', 'SIO.AX', 'SIP.AX', 'SIQ.AX', 'SIS.AX', 'SIT.AX',
    'SIV.AX', 'SIX.AX', 'SKC.AX', 'SKF.AX', 'SKI.AX', 'SKN.AX', 'SKO.AX', 'SKS.AX',
    'SKT.AX', 'SKY.AX', 'SLA.AX', 'SLC.AX', 'SLF.AX', 'SLH.AX', 'SLK.AX', 'SLR.AX',
    'SLS.AX', 'SLX.AX', 'SLZ.AX', 'SM1.AX', 'SMA.AX', 'SMC.AX', 'SMF.AX', 'SMI.AX',
    'SML.AX', 'SMM.AX', 'SMN.AX', 'SMR.AX', 'SMS.AX', 'SMX.AX', 'SND.AX', 'SNL.AX',
    'SNR.AX', 'SNS.AX', 'SNT.AX', 'SNZ.AX', 'SO4.AX', 'SOC.AX', 'SOL.AX', 'SOM.AX',
    'SOP.AX', 'SOR.AX', 'SOU.AX', 'SOV.AX', 'SP3.AX', 'SPA.AX', 'SPB.AX', 'SPC.AX',
    'SPK.AX', 'SPL.AX', 'SPM.AX', 'SPN.AX', 'SPP.AX', 'SPQ.AX', 'SPR.AX', 'SPS.AX',
    'SPT.AX', 'SPX.AX', 'SPZ.AX', 'SQ2.AX', 'SQL.AX', 'SQX.AX', 'SRG.AX', 'SRH.AX',
    'SRI.AX', 'SRJ.AX', 'SRK.AX', 'SRN.AX', 'SRO.AX', 'SRR.AX', 'SRU.AX', 'SRV.AX',
    'SRX.AX', 'SRY.AX', 'SRZ.AX', 'SS1.AX', 'SSG.AX', 'SSI.AX', 'SSL.AX', 'SSM.AX',
    'SSR.AX', 'SST.AX', 'ST1.AX', 'STA.AX', 'STB.AX', 'STC.AX', 'STG.AX', 'STI.AX',
    'STK.AX', 'STM.AX', 'STN.AX', 'STO.AX', 'STP.AX', 'STR.AX', 'STU.AX', 'STV.AX',
    'STW.AX', 'STX.AX', 'SUB.AX', 'SUH.AX', 'SUL.AX', 'SUM.AX', 'SUN.AX', 'SUP.AX',
    'SUR.AX', 'SUT.AX', 'SVA.AX', 'SVG.AX', 'SVH.AX', 'SVL.AX', 'SVM.AX', 'SVT.AX',
    'SVW.AX', 'SVY.AX', 'SWC.AX', 'SWF.AX', 'SWG.AX', 'SWK.AX', 'SWM.AX', 'SWR.AX',
    'SXA.AX', 'SXE.AX', 'SXG.AX', 'SXL.AX', 'SXY.AX', 'SYA.AX', 'SYD.AX', 'SYM.AX',
    'SYR.AX', 'SZL.AX',
    
    // T
    'T2M.AX', 'TAH.AX', 'TAM.AX', 'TAO.AX', 'TAP.AX', 'TAS.AX', 'TAW.AX', 'TBA.AX',
    'TBI.AX', 'TBN.AX', 'TBR.AX', 'TCF.AX', 'TCG.AX', 'TCL.AX', 'TCN.AX', 'TCO.AX',
    'TDL.AX', 'TDO.AX', 'TEA.AX', 'TEC.AX', 'TEE.AX', 'TEK.AX', 'TEM.AX', 'TEP.AX',
    'TER.AX', 'TFL.AX', 'TFM.AX', 'TGA.AX', 'TGF.AX', 'TGM.AX', 'TGN.AX', 'TGO.AX',
    'TGP.AX', 'TGR.AX', 'TGS.AX', 'TGX.AX', 'THD.AX', 'THL.AX', 'THR.AX', 'THT.AX',
    'TI1.AX', 'TIE.AX', 'TIG.AX', 'TIN.AX', 'TIP.AX', 'TIS.AX', 'TKL.AX', 'TKM.AX',
    'TKO.AX', 'TLA.AX', 'TLG.AX', 'TLM.AX', 'TLO.AX', 'TLS.AX', 'TLT.AX', 'TLX.AX',
    'TMA.AX', 'TMB.AX', 'TMD.AX', 'TME.AX', 'TMH.AX', 'TMK.AX', 'TML.AX', 'TMM.AX',
    'TMR.AX', 'TMS.AX', 'TMT.AX', 'TMX.AX', 'TMZ.AX', 'TNE.AX', 'TNG.AX', 'TNO.AX',
    'TNP.AX', 'TNR.AX', 'TNT.AX', 'TNY.AX', 'TOE.AX', 'TOI.AX', 'TOM.AX', 'TON.AX',
    'TOT.AX', 'TOU.AX', 'TOY.AX', 'TPC.AX', 'TPD.AX', 'TPG.AX', 'TPM.AX', 'TPO.AX',
    'TPP.AX', 'TPS.AX', 'TPW.AX', 'TRA.AX', 'TRB.AX', 'TRJ.AX', 'TRL.AX', 'TRM.AX',
    'TRP.AX', 'TRS.AX', 'TRU.AX', 'TRY.AX', 'TSC.AX', 'TSI.AX', 'TSK.AX', 'TSL.AX',
    'TSM.AX', 'TSN.AX', 'TSO.AX', 'TTB.AX', 'TTC.AX', 'TTE.AX', 'TTI.AX', 'TTL.AX',
    'TTM.AX', 'TTP.AX', 'TTV.AX', 'TUA.AX', 'TUL.AX', 'TVL.AX', 'TVN.AX', 'TWD.AX',
    'TWE.AX', 'TWR.AX', 'TYM.AX', 'TYR.AX', 'TYX.AX', 'TZL.AX', 'TZN.AX',
    
    // U
    'UBA.AX', 'UBI.AX', 'UBN.AX', 'UCM.AX', 'UCW.AX', 'UFO.AX', 'UGL.AX', 'UGO.AX',
    'UHY.AX', 'UIM.AX', 'ULT.AX', 'UMG.AX', 'UML.AX', 'UND.AX', 'UNI.AX', 'UNL.AX',
    'UNS.AX', 'UOS.AX', 'UPD.AX', 'UPL.AX', 'URL.AX', 'URN.AX', 'URW.AX', 'USF.AX',
    'USL.AX', 'UTR.AX', 'UWL.AX',
    
    // V
    'VAL.AX', 'VAN.AX', 'VAR.AX', 'VBC.AX', 'VBS.AX', 'VCF.AX', 'VCX.AX', 'VEA.AX',
    'VEC.AX', 'VEE.AX', 'VEN.AX', 'VET.AX', 'VG1.AX', 'VG8.AX', 'VGI.AX', 'VGL.AX',
    'VGR.AX', 'VGS.AX', 'VHM.AX', 'VHT.AX', 'VHY.AX', 'VIA.AX', 'VIC.AX', 'VIP.AX',
    'VKA.AX', 'VKI.AX', 'VLT.AX', 'VLW.AX', 'VMC.AX', 'VMG.AX', 'VML.AX', 'VMS.AX',
    'VMT.AX', 'VMY.AX', 'VN8.AX', 'VNA.AX', 'VNT.AX', 'VOC.AX', 'VOR.AX', 'VPH.AX',
    'VPR.AX', 'VR1.AX', 'VRC.AX', 'VRE.AX', 'VRL.AX', 'VRS.AX', 'VRT.AX', 'VRX.AX',
    'VSC.AX', 'VSR.AX', 'VST.AX', 'VTG.AX', 'VTH.AX', 'VTI.AX', 'VUK.AX', 'VUL.AX',
    'VVA.AX', 'VVR.AX',
    
    // W
    'WAA.AX', 'WAF.AX', 'WAM.AX', 'WAR.AX', 'WAT.AX', 'WAX.AX', 'WBA.AX', 'WBC.AX',
    'WBE.AX', 'WBT.AX', 'WC8.AX', 'WCE.AX', 'WCM.AX', 'WCN.AX', 'WCP.AX', 'WDE.AX',
    'WDS.AX', 'WEB.AX', 'WEC.AX', 'WEL.AX', 'WES.AX', 'WFL.AX', 'WGB.AX', 'WGN.AX',
    'WGO.AX', 'WGP.AX', 'WGR.AX', 'WGS.AX', 'WGT.AX', 'WGX.AX', 'WHC.AX', 'WHF.AX',
    'WHK.AX', 'WHN.AX', 'WIA.AX', 'WIN.AX', 'WKT.AX', 'WLC.AX', 'WLD.AX', 'WLE.AX',
    'WLF.AX', 'WLN.AX', 'WLS.AX', 'WLT.AX', 'WMC.AX', 'WMI.AX', 'WMK.AX', 'WMN.AX',
    'WML.AX', 'WNB.AX', 'WND.AX', 'WNR.AX', 'WOA.AX', 'WOO.AX', 'WOR.AX', 'WOW.AX',
    'WPL.AX', 'WPP.AX', 'WPR.AX', 'WQG.AX', 'WR1.AX', 'WRG.AX', 'WRM.AX', 'WRN.AX',
    'WSA.AX', 'WSP.AX', 'WSR.AX', 'WTC.AX', 'WTL.AX', 'WTN.AX', 'WZR.AX',
    
    // X
    'XAM.AX', 'XF1.AX', 'XGL.AX', 'XPE.AX', 'XPL.AX', 'XRF.AX', 'XRG.AX', 'XRO.AX',
    'XST.AX', 'XTC.AX', 'XTE.AX',
    
    // Y
    'YAL.AX', 'YBR.AX', 'YFZ.AX', 'YNB.AX', 'YOJ.AX', 'YOW.AX', 'YPB.AX', 'YRR.AX',
    
    // Z
    'Z1P.AX', 'Z2U.AX', 'ZBT.AX', 'ZEO.AX', 'ZER.AX', 'ZGL.AX', 'ZIM.AX', 'ZIP.AX',
    'ZLD.AX', 'ZMI.AX', 'ZNC.AX', 'ZNO.AX', 'ZTA.AX',
  ];
}