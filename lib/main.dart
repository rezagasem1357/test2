import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:excel/excel.dart' as ex;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const DeliveryApp());
}

class DeliveryApp extends StatelessWidget {
  const DeliveryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
  title: 'تحویل بار',
  debugShowCheckedModeBanner: false,
  theme: ThemeData(
    primarySwatch: Colors.blue,
    useMaterial3: true,
    // fontFamily: 'Vazir',  // ← حذف شود
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.light,
    ),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      centerTitle: true,
    ),
  ),
  locale: const Locale('fa'),
  supportedLocales: const [Locale('fa')],
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: const Directionality(
    textDirection: TextDirection.rtl,
    child: DeliveryScreen(),
  ),
);
  }
}

class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({super.key});

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  List<DeliveryItem> _currentItems = [];
  List<DeliveryItem> _filteredItems = [];
  List<Map<String, dynamic>> _manifestSearchResults = [];
  List<DeliveryManifest> _savedManifests = [];
  List<MasterProduct> _masterDatabase = [];
  List<String> _smartLogs = [];

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _purchasePriceController =
      TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _barcodeController = TextEditingController();
  final TextEditingController _packageSizeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isSearching = false;
  String _selectedUnit = 'عددی';
  bool _isLoading = false;
  bool _isPackageUnit = false;
  bool _isViewingManifest = false;
  DeliveryManifest? _viewingManifest;

  @override
  void initState() {
    super.initState();
    _loadSavedManifests();
    _loadMasterDatabase();
    _loadSmartLogs();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _purchasePriceController.dispose();
    _searchController.dispose();
    _barcodeController.dispose();
    _packageSizeController.dispose();
    super.dispose();
  }

  // ==================== توابع کمکی ====================

  String _formatNumber(String value) {
    if (value.isEmpty) return '';
    final number = int.tryParse(value.replaceAll(',', ''));
    if (number == null) return value;
    return number.toString().replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
          (match) => '${match[1]},',
        );
  }

  String _formatPrice(int price) {
    return _formatNumber(price.toString());
  }

  int _convertPrice(String priceStr) {
    if (priceStr.isEmpty) return 0;
    final cleanPrice = int.tryParse(priceStr.replaceAll(',', ''));
    if (cleanPrice == null) return 0;
    return cleanPrice;
  }

  String _displayPrice(int price) {
    return '${_formatPrice(price)} ریال';
  }

  int _getNextManifestNumber() {
    return _savedManifests.length + 1;
  }

  // ==================== ذخیره‌سازی بانک اطلاعاتی پایه ====================

  Future<void> _loadMasterDatabase() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('master_database');
    if (data != null) {
      try {
        final List<dynamic> decoded = jsonDecode(data);
        setState(() {
          _masterDatabase =
              decoded.map((e) => MasterProduct.fromJson(e)).toList();
        });
      } catch (e) {}
    }
  }

  Future<void> _saveMasterDatabase() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_masterDatabase.map((e) => e.toJson()).toList());
    await prefs.setString('master_database', encoded);
  }

  // ==================== جستجوی بارکد در بانک اطلاعات ====================

  Future<void> _searchLocalBarcode() async {
    final barcode = _barcodeController.text.trim();
    if (barcode.isEmpty) {
      _showSuccessMessage('لطفاً بارکد را وارد کنید ❌');
      return;
    }

    // ۱. ابتدا جستجو در بانک اطلاعات اصلی پایه
    final masterIndex =
        _masterDatabase.indexWhere((element) => element.barcode == barcode);
    if (masterIndex != -1) {
      final product = _masterDatabase[masterIndex];
      _nameController.text = product.name;
      _purchasePriceController.text = _formatPrice(product.purchasePrice);
      _selectedUnit = product.unit;
      _isPackageUnit = (product.unit == 'بسته‌ای');
      if (_isPackageUnit && product.packageSize > 0) {
        _packageSizeController.text = product.packageSize.toString();
      }
      _showSuccessMessage('کالا از بانک اطلاعات یافت شد ✅');
      return;
    }

    // ۲. در صورت عدم وجود، جستجو در سوابق بارنامه‌ها
    for (var manifest in _savedManifests) {
      for (var item in manifest.items) {
        if (item.barcode == barcode) {
          _nameController.text = item.name;
          _purchasePriceController.text = _formatPrice(item.purchasePrice);
          _selectedUnit = item.unit;
          _isPackageUnit = item.unit == 'بسته‌ای';
          if (_isPackageUnit && item.packageSize > 0) {
            _packageSizeController.text = item.packageSize.toString();
          }
          _showSuccessMessage('کالا از سابقه بارنامه‌ها پیدا شد ✅');
          return;
        }
      }
    }

    _showSuccessMessage('یافت نشد ❌');
  }

  Future<bool> _checkInternet() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    return !connectivityResult.contains(ConnectivityResult.none);
  }

  Future<void> _searchOnlineBarcode() async {
    final isOnline = await _checkInternet();
    if (!isOnline) {
      _showSuccessMessage('اینترنت خاموش است! ⚠️');
      return;
    }

    final barcode = _barcodeController.text.trim();
    if (barcode.isEmpty) {
      _showSuccessMessage('لطفاً بارکد را وارد کنید ❌');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final response = await http.get(
        Uri.parse('https://api.upcitemdb.com/prod/trial/lookup?upc=$barcode'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['items'] != null && (data['items'] as List).isNotEmpty) {
          final item = data['items'][0];
          _nameController.text = item['title'] ?? '';
          _showSuccessMessage('اطلاعات آنلاین دریافت شد ✅');
        } else {
          _showSuccessMessage('یافت نشد ❌');
        }
      } else {
        _showSuccessMessage('خطا در دریافت اطلاعات ❌');
      }
    } catch (e) {
      _showSuccessMessage('خطا در برقراری ارتباط ❌');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _scanBarcode() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const BarcodeScannerScreen()),
    );

    if (!mounted) return;

    if (result != null && result.isNotEmpty) {
      setState(() {
        _barcodeController.text = result;
      });
      _showSuccessMessage('بارکد اسکن شد ✅');
      await _searchLocalBarcode();
    }
  }

  // ==================== خروجی اکسل و PDF ====================

  Future<void> _exportToExcel(DeliveryManifest manifest) async {
    var excel = ex.Excel.createExcel();
    ex.Sheet sheetObject = excel['بارنامه_${manifest.number}'];
    excel.delete('Sheet1');

    sheetObject.appendRow([
      ex.TextCellValue('نام کالا'),
      ex.TextCellValue('بارکد'),
      ex.TextCellValue('واحد'),
      ex.TextCellValue('تعداد'),
      ex.TextCellValue('تعداد در بسته'),
      ex.TextCellValue('تعداد کل واقعی'),
      ex.TextCellValue('قیمت واحد (ریال)'),
      ex.TextCellValue('قیمت کل (ریال)'),
    ]);

    for (var item in manifest.items) {
      sheetObject.appendRow([
        ex.TextCellValue(item.name),
        ex.TextCellValue(item.barcode),
        ex.TextCellValue(item.unit),
        ex.IntCellValue(item.quantity),
        ex.IntCellValue(item.packageSize),
        ex.IntCellValue(item.realQuantity),
        ex.IntCellValue(item.purchasePrice),
        ex.IntCellValue(item.purchasePrice * item.realQuantity),
      ]);
    }

    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/Manifest_${manifest.number}.xlsx';
    final fileBytes = excel.save();
    if (fileBytes != null) {
      File(filePath)
        ..createSync(recursive: true)
        ..writeAsBytesSync(fileBytes);
      await Share.shareXFiles([XFile(filePath)],
          text: 'خروجی اکسل بارنامه شماره ${manifest.number}');
    }
  }

  Future<void> _exportToPdf(DeliveryManifest manifest) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.vazirmatnRegular();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Header(
                  level: 0,
                  child: pw.Text(
                      'بارنامه شماره ${manifest.number} - تاریخ: ${manifest.date}',
                      style: pw.TextStyle(
                          font: font,
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold)),
                ),
                pw.SizedBox(height: 10),
                pw.Table.fromTextArray(
                  headers: [
                    'نام کالا',
                    'بارکد',
                    'واحد',
                    'تعداد',
                    'قیمت واحد',
                    'جمع کل'
                  ],
                  data: manifest.items.map((item) {
                    return [
                      item.name,
                      item.barcode,
                      item.unit,
                      '${item.quantity}${item.packageSize > 0 ? ' (${item.realQuantity})' : ''}',
                      _formatPrice(item.purchasePrice),
                      _formatPrice(item.purchasePrice * item.realQuantity),
                    ];
                  }).toList(),
                  cellStyle: pw.TextStyle(font: font, fontSize: 10),
                  headerStyle: pw.TextStyle(
                      font: font, fontSize: 11, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 20),
                pw.Text(
                    'مجموع کل بارنامه: ${_displayPrice(manifest.totalPrice)}',
                    style: pw.TextStyle(
                        font: font,
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold)),
              ],
            ),
          );
        },
      ),
    );

    await Printing.sharePdf(
        bytes: await pdf.save(), filename: 'Manifest_${manifest.number}.pdf');
  }

  void _showSuccessMessage(String message) {
    OverlayEntry overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).size.height / 2 - 60,
        left: MediaQuery.of(context).size.width / 2 - 120,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 240,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            decoration: BoxDecoration(
              color: message.contains('❌') ||
                      message.contains('خطا') ||
                      message.contains('⚠️')
                  ? Colors.red.shade700
                  : Colors.green.shade700,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  message.contains('❌') ||
                          message.contains('خطا') ||
                          message.contains('⚠️')
                      ? Icons.error_outline
                      : Icons.check_circle,
                  color: Colors.white,
                  size: 40,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(overlayEntry);
    Future.delayed(const Duration(seconds: 2), () {
      overlayEntry.remove();
    });
  }

  void _addSmartLog(String message) {
    setState(() {
      final timestamp = DateTime.now();
      final time =
          '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
      _smartLogs.insert(0, '[$time] $message');
    });
    _saveSmartLogs();
  }

  Future<void> _loadSmartLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final logsJson = prefs.getString('smart_logs');
    if (logsJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(logsJson);
        setState(() {
          _smartLogs = decoded.map((item) => item.toString()).toList();
        });
      } catch (e) {}
    }
  }

  Future<void> _saveSmartLogs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('smart_logs', jsonEncode(_smartLogs));
  }

  void _clearSmartLogs() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('پاک کردن گزارش هوشمند', textAlign: TextAlign.right),
        content: const Text('آیا از پاک کردن همه گزارش‌های هوشمند مطمئن هستید؟',
            textAlign: TextAlign.right),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('انصراف'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              setState(() {
                _smartLogs.clear();
              });
              _saveSmartLogs();
              Navigator.pop(context);
              _showSuccessMessage('گزارش‌ها پاک شدند 🗑️');
            },
            child: const Text('پاک کردن همه'),
          ),
        ],
      ),
    );
  }

  void _searchItems(String query) {
    setState(() {
      _isSearching = query.isNotEmpty;
      _filteredItems.clear();
      _manifestSearchResults.clear();

      if (query.isEmpty) {
        _isSearching = false;
        return;
      }

      final searchTerm = query.toLowerCase().trim();

      final currentResults = _currentItems
          .where((item) =>
              item.name.toLowerCase().contains(searchTerm) ||
              item.barcode.contains(searchTerm))
          .toList();
      _filteredItems = currentResults;

      for (var manifest in _savedManifests) {
        for (var item in manifest.items) {
          if (item.name.toLowerCase().contains(searchTerm) ||
              item.barcode.contains(searchTerm)) {
            _manifestSearchResults.add({
              'manifest': manifest,
              'item': item,
            });
          }
        }
      }
    });
  }

  void _clearControllers() {
    _nameController.clear();
    _quantityController.clear();
    _purchasePriceController.clear();
    _barcodeController.clear();
    _packageSizeController.clear();
    setState(() {
      _selectedUnit = 'عددی';
      _isPackageUnit = false;
    });
  }

  void _showAddDialog({DeliveryManifest? targetManifest}) {
    _clearControllers();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(
              targetManifest != null
                  ? 'افزودن کالا به بارنامه شماره ${targetManifest.number}'
                  : 'اضافه کردن کالا',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            content: Form(
              key: _formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _barcodeController,
                            textAlign: TextAlign.right,
                            decoration: InputDecoration(
                              labelText: 'شماره بارکد',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              hintText: 'اسکن یا دستی',
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        IconButton(
                          icon:
                              const Icon(Icons.camera_alt, color: Colors.blue),
                          onPressed: _scanBarcode,
                          tooltip: 'اسکن دوربین',
                        ),
                        IconButton(
                          icon: const Icon(Icons.saved_search,
                              color: Colors.amber),
                          onPressed: _searchLocalBarcode,
                          tooltip: 'جستجوی حافظه',
                        ),
                        IconButton(
                          icon: const Icon(Icons.language, color: Colors.green),
                          onPressed: _searchOnlineBarcode,
                          tooltip: 'جستجوی اینترنتی',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _nameController,
                      textAlign: TextAlign.right,
                      decoration: InputDecoration(
                        labelText: 'نام کالا',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      validator: (value) => (value == null || value.isEmpty)
                          ? 'لطفاً نام کالا را وارد کنید'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('واحد سنجش:'),
                        const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _selectedUnit,
                            decoration: InputDecoration(
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12))),
                            items: const [
                              DropdownMenuItem(
                                  value: 'عددی', child: Text('عددی')),
                              DropdownMenuItem(
                                  value: 'کیلویی', child: Text('کیلویی')),
                              DropdownMenuItem(
                                  value: 'بسته‌ای', child: Text('بسته‌ای')),
                            ],
                            onChanged: (value) {
                              setDialogState(() {
                                _selectedUnit = value!;
                                _isPackageUnit = (value == 'بسته‌ای');
                                if (!_isPackageUnit)
                                  _packageSizeController.clear();
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _quantityController,
                      textAlign: TextAlign.right,
                      decoration: InputDecoration(
                        labelText:
                            'تعداد (${_selectedUnit == 'بسته‌ای' ? 'بسته' : _selectedUnit})',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty)
                          return 'لطفاً تعداد را وارد کنید';
                        if (int.tryParse(value) == null)
                          return 'عدد معتبر وارد کنید';
                        return null;
                      },
                    ),
                    if (_isPackageUnit) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _packageSizeController,
                        textAlign: TextAlign.right,
                        decoration: InputDecoration(
                          labelText: 'تعداد داخل هر بسته',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                          hintText: 'مثلاً 12',
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (_isPackageUnit) {
                            if (value == null || value.isEmpty)
                              return 'ورود تعداد داخل بسته الزامی است';
                            if (int.tryParse(value) == null ||
                                int.parse(value) <= 0)
                              return 'عدد معتبر وارد کنید';
                          }
                          return null;
                        },
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _purchasePriceController,
                      textAlign: TextAlign.right,
                      decoration: InputDecoration(
                        labelText: 'قیمت خرید واحد (ریال)',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        prefixText: 'ریال ',
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        final formatted = _formatNumber(value);
                        if (formatted != value) {
                          _purchasePriceController.value = TextEditingValue(
                            text: formatted,
                            selection: TextSelection.collapsed(
                                offset: formatted.length),
                          );
                        }
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty)
                          return 'لطفاً قیمت خرید را وارد کنید';
                        if (int.tryParse(value.replaceAll(',', '')) == null)
                          return 'عدد معتبر وارد کنید';
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('انصراف'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    final qty = int.parse(_quantityController.text);
                    final packageSize =
                        _isPackageUnit && _packageSizeController.text.isNotEmpty
                            ? int.parse(_packageSizeController.text)
                            : 0;

                    final calculatedRealQty =
                        _isPackageUnit ? (qty * packageSize) : qty;

                    final newItem = DeliveryItem(
                      name: _nameController.text,
                      quantity: qty,
                      realQuantity: calculatedRealQty,
                      purchasePrice:
                          _convertPrice(_purchasePriceController.text),
                      barcode: _barcodeController.text.isNotEmpty
                          ? _barcodeController.text
                          : DateTime.now().millisecondsSinceEpoch.toString(),
                      date: DateTime.now().millisecondsSinceEpoch.toString(),
                      unit: _selectedUnit,
                      packageSize: packageSize,
                    );

                    if (targetManifest != null) {
                      setState(() {
                        targetManifest.items.add(newItem);
                        targetManifest.totalPrice +=
                            newItem.purchasePrice * newItem.realQuantity;
                      });
                      _addSmartLog('➕ کالا "${newItem.name}" اضافه شد');
                      _saveManifestChanges(targetManifest);
                      Navigator.pop(context);
                      _showSuccessMessage('کالا اضافه شد ✅');
                    } else {
                      setState(() {
                        _currentItems.add(newItem);
                        if (_searchController.text.isNotEmpty) {
                          _searchItems(_searchController.text);
                        }
                      });
                      _addSmartLog('✅ کالا "${_nameController.text}" اضافه شد');
                      _clearControllers();
                      Navigator.pop(context);
                      _showSuccessMessage('کالا اضافه شد ✅');
                    }
                  }
                },
                child: const Text('افزودن'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _removeItem(int index) {
    setState(() {
      if (_isSearching && _filteredItems.isNotEmpty) {
        final itemToRemove = _filteredItems[index];
        _currentItems.remove(itemToRemove);
        _filteredItems.removeAt(index);
        if (_filteredItems.isEmpty) {
          _isSearching = false;
          _searchController.clear();
        }
      } else {
        _currentItems.removeAt(index);
      }
    });
  }

  int get _totalPurchasePrice {
    int total = 0;
    for (var item in _currentItems) {
      total += item.purchasePrice * item.realQuantity;
    }
    return total;
  }

  void _submitDelivery() async {
    final TextEditingController dateController = TextEditingController();
    dateController.text = _getTodayDate();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ثبت نهایی تحویل بار', textAlign: TextAlign.right),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('لطفاً تاریخ بارنامه را وارد کنید:'),
            const SizedBox(height: 16),
            TextFormField(
              controller: dateController,
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                labelText: 'تاریخ (مثلاً ۱۴۰۴/۰۵/۱۵)',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.calendar_today),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [Colors.green.shade50, Colors.green.shade100]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('تعداد کالاها: ${_currentItems.length}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('مجموع قیمت: ${_displayPrice(_totalPurchasePrice)}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('شماره بارنامه: ${_getNextManifestNumber()}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.blue)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('انصراف')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () async {
              final manifestDate = dateController.text.isEmpty
                  ? _getTodayDate()
                  : dateController.text;

              final manifest = DeliveryManifest(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                number: _getNextManifestNumber(),
                date: manifestDate,
                items: List.from(_currentItems),
                totalPrice: _totalPurchasePrice,
                createdAt: DateTime.now().millisecondsSinceEpoch.toString(),
              );

              await _saveManifest(manifest);
              _addSmartLog('📋 بارنامه شماره ${manifest.number} ثبت شد');

              setState(() {
                _currentItems.clear();
                _filteredItems.clear();
                _searchController.clear();
                _isSearching = false;
              });

              Navigator.pop(context);
              _showSuccessMessage('بارنامه ثبت شد ✅');
            },
            child: const Text('ثبت نهایی'),
          ),
        ],
      ),
    );
  }

  String _getTodayDate() {
    final now = DateTime.now();
    final persianYear = now.year - 621;
    return '$persianYear/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _saveManifest(DeliveryManifest manifest) async {
    final prefs = await SharedPreferences.getInstance();
    final manifestsJson = _savedManifests.map((m) => m.toJson()).toList();
    manifestsJson.add(manifest.toJson());
    await prefs.setString('delivery_manifests', jsonEncode(manifestsJson));

    setState(() {
      _savedManifests.add(manifest);
    });
  }

  Future<void> _loadSavedManifests() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final manifestsJson = prefs.getString('delivery_manifests');

    if (manifestsJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(manifestsJson);
        setState(() {
          _savedManifests =
              decoded.map((item) => DeliveryManifest.fromJson(item)).toList();
          _isLoading = false;
        });
      } catch (e) {
        setState(() => _isLoading = false);
      }
    } else {
      setState(() => _isLoading = false);
    }
  }

  void _startEditingManifest(DeliveryManifest manifest) {
    final dateController = TextEditingController(text: manifest.date);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('ویرایش بارنامه شماره ${manifest.number}',
            textAlign: TextAlign.right),
        content: StatefulBuilder(
          builder: (context, setStateDialog) {
            return SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: dateController,
                    textAlign: TextAlign.right,
                    decoration: InputDecoration(
                      labelText: 'تاریخ بارنامه',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.edit_calendar),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('لیست کالاها:',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: Colors.green),
                        onPressed: () {
                          Navigator.pop(context);
                          _showAddDialog(targetManifest: manifest);
                        },
                      ),
                    ],
                  ),
                  Container(
                    height: 200,
                    decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8)),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: manifest.items.length,
                      itemBuilder: (context, index) {
                        final item = manifest.items[index];
                        return ListTile(
                          title: Text(item.name),
                          subtitle: Text(
                              'تعداد: ${item.quantity} | ${_displayPrice(item.purchasePrice)}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle_outline,
                                color: Colors.red),
                            onPressed: () {
                              setState(() {
                                final removedItem = manifest.items[index];
                                manifest.items.removeAt(index);
                                manifest.totalPrice -=
                                    removedItem.purchasePrice *
                                        removedItem.realQuantity;
                              });
                              setStateDialog(() {});
                              _saveManifestChanges(manifest);
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('انصراف')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange, foregroundColor: Colors.white),
            onPressed: () async {
              setState(() => manifest.date = dateController.text);
              await _saveManifestChanges(manifest);
              Navigator.pop(context);
              _showSuccessMessage('تغییرات ذخیره شد ✅');
            },
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveManifestChanges(DeliveryManifest manifest) async {
    final prefs = await SharedPreferences.getInstance();
    final manifestsJson = _savedManifests.map((m) => m.toJson()).toList();
    await prefs.setString('delivery_manifests', jsonEncode(manifestsJson));
  }

  Future<void> _deleteManifest(DeliveryManifest manifest) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('حذف بارنامه شماره ${manifest.number}',
            textAlign: TextAlign.right),
        content: Text('آیا از حذف مطمئن هستید؟', textAlign: TextAlign.right),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('انصراف')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              setState(() => _savedManifests.remove(manifest));
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('delivery_manifests',
                  jsonEncode(_savedManifests.map((m) => m.toJson()).toList()));
              Navigator.pop(context);
              if (_isViewingManifest && _viewingManifest?.id == manifest.id) {
                setState(() {
                  _isViewingManifest = false;
                  _viewingManifest = null;
                });
              }
              _showSuccessMessage('بارنامه حذف شد 🗑️');
            },
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }

  void _viewManifest(DeliveryManifest manifest) {
    setState(() {
      _viewingManifest = manifest;
      _isViewingManifest = true;
    });
  }

  void _goBackToMain() {
    setState(() {
      _isViewingManifest = false;
      _viewingManifest = null;
    });
  }

  void _cancelDelivery() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('لغو عملیات', textAlign: TextAlign.right),
        content: const Text('آیا از لغو این محموله مطمئن هستید؟',
            textAlign: TextAlign.right),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('انصراف')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              setState(() {
                _currentItems.clear();
                _filteredItems.clear();
                _searchController.clear();
                _isSearching = false;
              });
              Navigator.pop(context);
              _showSuccessMessage('محموله لغو شد ❌');
            },
            child: const Text('بله، لغو شود'),
          ),
        ],
      ),
    );
  }

  // ==================== کشو / منوی سمت راست (Drawer) ====================

  Widget _buildAppDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: Colors.blue),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.inventory, size: 50, color: Colors.white),
                SizedBox(height: 10),
                Text(
                  'منوی مدیریت تحویل بار',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.home, color: Colors.blue),
            title: const Text('صفحه اصلی'),
            onTap: () {
              Navigator.pop(context);
              _goBackToMain();
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.storage, color: Colors.purple),
            title: const Text('بانک اطلاعات کالاها'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => DatabaseScreen(
                    masterDatabase: _masterDatabase,
                    onDatabaseUpdated: (updatedList) {
                      setState(() {
                        _masterDatabase = updatedList;
                      });
                      _saveMasterDatabase();
                    },
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ==================== ویجت‌های نمایشی ====================

  Widget _buildSmartLogs() {
    if (_smartLogs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('📊 گزارش هوشمند:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: _clearSmartLogs,
            ),
          ],
        ),
        Container(
          height: 100,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: ListView.builder(
            reverse: true,
            itemCount: _smartLogs.length,
            itemBuilder: (context, index) {
              return Text(
                _smartLogs[index],
                style: const TextStyle(fontSize: 12),
                textAlign: TextAlign.right,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSearchResults() {
    final totalResults = _filteredItems.length + _manifestSearchResults.length;

    if (totalResults == 0) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Text('🔍 هیچ کالایی با این نام یا بارکد پیدا نشد',
              style: TextStyle(fontSize: 16)),
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('نتایج پیدا شده: $totalResults',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.blue)),
          ),
          ..._filteredItems.map((item) => ListTile(
                title: Text(item.name, textAlign: TextAlign.right),
                subtitle: Text(
                    'تعداد: ${item.quantity} | بارکد: ${item.barcode}',
                    textAlign: TextAlign.right),
              )),
        ],
      ),
    );
  }

  Widget _buildMainView() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              labelText: '🔍 جستجوی پیشرفته در بارنامه‌ها',
              hintText: 'نام یا بارکد کالا را وارد کنید...',
              prefixIcon: const Icon(Icons.search),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _isSearching = false;
                          _filteredItems.clear();
                          _manifestSearchResults.clear();
                        });
                      },
                    )
                  : null,
            ),
            onChanged: _searchItems,
          ),
        ),
        _buildSmartLogs(),
        if (_isSearching)
          Expanded(child: _buildSearchResults())
        else
          Expanded(
            child: _currentItems.isEmpty && _savedManifests.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.inventory_2_outlined,
                            size: 80, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('هیچ کالا یا بارنامه‌ای وجود ندارد',
                            style: TextStyle(fontSize: 18)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _currentItems.isNotEmpty
                        ? _currentItems.length
                        : _savedManifests.length,
                    itemBuilder: (context, index) {
                      if (_currentItems.isNotEmpty) {
                        return _buildItemCard(index);
                      } else {
                        return GestureDetector(
                          onTap: () => _viewManifest(_savedManifests[index]),
                          child: _buildManifestCard(index),
                        );
                      }
                    },
                  ),
          ),
        if (_currentItems.isNotEmpty && !_isSearching) _buildBottomButtons(),
      ],
    );
  }

  Widget _buildItemCard(int index) {
    final item = _currentItems[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(item.name,
            style: const TextStyle(fontWeight: FontWeight.bold),
            textAlign: TextAlign.right),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('تعداد: ${item.quantity} ${item.unit}',
                textAlign: TextAlign.right),
            Text('قیمت خرید: ${_displayPrice(item.purchasePrice)}',
                textAlign: TextAlign.right),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: () => _removeItem(index),
        ),
      ),
    );
  }

  Widget _buildManifestCard(int index) {
    final manifest = _savedManifests[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text('بارنامه شماره ${manifest.number}',
            style: const TextStyle(fontWeight: FontWeight.bold),
            textAlign: TextAlign.right),
        subtitle: Text(
            'تاریخ: ${manifest.date} | مجموع: ${_displayPrice(manifest.totalPrice)}',
            textAlign: TextAlign.right),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
                icon: const Icon(Icons.edit, color: Colors.orange),
                onPressed: () => _startEditingManifest(manifest)),
            IconButton(
                icon: const Icon(Icons.grid_on, color: Colors.green),
                onPressed: () => _exportToExcel(manifest)),
            IconButton(
                icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                onPressed: () => _exportToPdf(manifest)),
            IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => _deleteManifest(manifest)),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomButtons() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.grey.shade50,
          border: Border(top: BorderSide(color: Colors.grey.shade300))),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('مجموع قیمت:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text(_displayPrice(_totalPurchasePrice),
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                  onPressed: _cancelDelivery,
                  child: const Text('لغو'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                  onPressed: _submitDelivery,
                  child: const Text('ثبت نهایی'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildManifestView() {
    final manifest = _viewingManifest!;
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: [
              Text('بارنامه شماره ${manifest.number}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 8),
              Text('تاریخ: ${manifest.date}'),
              Text('مجموع کل: ${_displayPrice(manifest.totalPrice)}',
                  style: const TextStyle(
                      color: Colors.orange, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: manifest.items.length,
            itemBuilder: (context, index) {
              final item = manifest.items[index];
              return ListTile(
                title: Text(item.name, textAlign: TextAlign.right),
                subtitle: Text(
                    'تعداد: ${item.quantity} | قیمت: ${_displayPrice(item.purchasePrice)}',
                    textAlign: TextAlign.right),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isViewingManifest
              ? 'بارنامه شماره ${_viewingManifest!.number}'
              : '📦 مدیریت تحویل بار',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (!_isViewingManifest)
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => _showAddDialog(),
            ),
        ],
        leading: _isViewingManifest
            ? IconButton(
                icon: const Icon(Icons.arrow_back), onPressed: _goBackToMain)
            : Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
      ),
      drawer: _buildAppDrawer(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isViewingManifest
              ? _buildManifestView()
              : _buildMainView(),
    );
  }
}

// ==================== صفحه اختصاصی بانک اطلاعات ====================

class DatabaseScreen extends StatefulWidget {
  final List<MasterProduct> masterDatabase;
  final Function(List<MasterProduct>) onDatabaseUpdated;

  const DatabaseScreen({
    super.key,
    required this.masterDatabase,
    required this.onDatabaseUpdated,
  });

  @override
  State<DatabaseScreen> createState() => _DatabaseScreenState();
}

class _DatabaseScreenState extends State<DatabaseScreen> {
  late List<MasterProduct> _list;

  @override
  void initState() {
    super.initState();
    _list = List.from(widget.masterDatabase);
  }

  Future<void> _importData() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (result != null && result.files.single.path != null) {
        var bytes = File(result.files.single.path!).readAsBytesSync();
        var excel = ex.Excel.decodeBytes(bytes);

        List<MasterProduct> importedProducts = [];

        for (var table in excel.tables.keys) {
          for (var row in excel.tables[table]!.rows.skip(1)) {
            if (row.length >= 4) {
              final name = row[0]?.value?.toString() ?? '';
              final barcode = row[1]?.value?.toString() ?? '';
              final unit = row[2]?.value?.toString() ?? 'عددی';
              final price = int.tryParse(row[3]?.value?.toString() ?? '0') ?? 0;

              if (name.isNotEmpty && barcode.isNotEmpty) {
                importedProducts.add(MasterProduct(
                  name: name,
                  barcode: barcode,
                  unit: unit,
                  purchasePrice: price,
                ));
              }
            }
          }
        }

        setState(() {
          _list.addAll(importedProducts);
        });

        widget.onDatabaseUpdated(_list);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '${importedProducts.length} کالا به بانک اطلاعات افزوده شد ✅')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('خطا در خواندن فایل اکسل ❌')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('بانک اطلاعات کالاها'),
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // راهنما و قالب
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Row(
                        children: [
                          Icon(Icons.help_outline, color: Colors.blue),
                          SizedBox(width: 8),
                          Text('راهنما و قالب نمونه فایل اکسل',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                          'برای وارد کردن اطلاعات پایه کالاها، فایل اکسل شما باید دارای ۴ ستون با ترتیب زیر باشد:'),
                      SizedBox(height: 4),
                      Text(
                          'ستون ۱: نام کالا | ستون ۲: شماره بارکد | ستون ۳: واحد سنجش | ستون ۴: قیمت خرید (ریال)',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // دکمه دریافت اطلاعات
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.file_upload),
                  label: const Text('دریافت اطلاعات از فایل اکسل (.xlsx)'),
                  onPressed: _importData,
                ),
              ),
              const SizedBox(height: 24),
              const Text('لیست بانک اطلاعات کالاها:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              _list.isEmpty
                  ? const Center(
                      child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('بانک اطلاعات خالی است')))
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _list.length,
                      itemBuilder: (context, index) {
                        final item = _list[index];
                        return Card(
                          child: ListTile(
                            title: Text(item.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text(
                                'بارکد: ${item.barcode} | واحد: ${item.unit}'),
                            trailing: Text('${item.purchasePrice} ریال',
                                style: const TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold)),
                          ),
                        );
                      },
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== کلاس‌های مدل داده ====================

class MasterProduct {
  final String name;
  final String barcode;
  final String unit;
  final int purchasePrice;
  final int packageSize;

  MasterProduct({
    required this.name,
    required this.barcode,
    required this.unit,
    required this.purchasePrice,
    this.packageSize = 0,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'barcode': barcode,
        'unit': unit,
        'purchasePrice': purchasePrice,
        'packageSize': packageSize,
      };

  factory MasterProduct.fromJson(Map<String, dynamic> json) => MasterProduct(
        name: json['name'],
        barcode: json['barcode'],
        unit: json['unit'] ?? 'عددی',
        purchasePrice: json['purchasePrice'] ?? 0,
        packageSize: json['packageSize'] ?? 0,
      );
}

class DeliveryItem {
  final String name;
  final int quantity;
  final int realQuantity;
  final int purchasePrice;
  final String barcode;
  final String date;
  final String unit;
  final int packageSize;

  DeliveryItem({
    required this.name,
    required this.quantity,
    required this.realQuantity,
    required this.purchasePrice,
    required this.barcode,
    required this.date,
    required this.unit,
    required this.packageSize,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'quantity': quantity,
        'realQuantity': realQuantity,
        'purchasePrice': purchasePrice,
        'barcode': barcode,
        'date': date,
        'unit': unit,
        'packageSize': packageSize,
      };

  factory DeliveryItem.fromJson(Map<String, dynamic> json) => DeliveryItem(
        name: json['name'],
        quantity: json['quantity'],
        realQuantity: json['realQuantity'] ?? json['quantity'],
        purchasePrice: json['purchasePrice'] ?? 0,
        barcode: json['barcode'],
        date: json['date'],
        unit: json['unit'] ?? 'عددی',
        packageSize: json['packageSize'] ?? 0,
      );
}

class DeliveryManifest {
  String id;
  int number;
  String date;
  List<DeliveryItem> items;
  int totalPrice;
  String createdAt;

  DeliveryManifest({
    required this.id,
    required this.number,
    required this.date,
    required this.items,
    required this.totalPrice,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'date': date,
        'items': items.map((item) => item.toJson()).toList(),
        'totalPrice': totalPrice,
        'createdAt': createdAt,
      };

  factory DeliveryManifest.fromJson(Map<String, dynamic> json) {
    final itemsList = (json['items'] as List)
        .map((item) => DeliveryItem.fromJson(item))
        .toList();
    return DeliveryManifest(
      id: json['id'],
      number: json['number'] ?? 0,
      date: json['date'],
      items: itemsList,
      totalPrice: json['totalPrice'],
      createdAt: json['createdAt'],
    );
  }
}

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _scanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleBarcode(BarcodeCapture capture) {
    if (_scanned) return;

    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;

      if (value != null && value.isNotEmpty) {
        _scanned = true;
        _controller.stop();
        Navigator.pop(context, value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('اسکن بارکد'),
        foregroundColor: Colors.white,
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _handleBarcode,
          ),
          Center(
            child: Container(
              width: 280,
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 50,
            child: Text(
              'بارکد را داخل کادر قرار دهید',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
