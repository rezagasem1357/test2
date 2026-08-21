import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_barcode_scanner/flutter_barcode_scanner.dart';
import 'dart:convert';

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
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: true,
        ),
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      locale: const Locale('fa'),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: DeliveryScreen(),
      ),
      debugShowCheckedModeBanner: false,
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
  List<String> _smartLogs = [];
  
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _purchasePriceController = TextEditingController();
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

  // ==================== اسکن بارکد با دوربین ====================
  
  Future<void> _scanBarcode() async {
    try {
      String barcode = await FlutterBarcodeScanner.scanBarcode(
        '#ff6666', // رنگ خط اسکن
        'انصراف', // متن دکمه انصراف
        true, // فعال بودن فلش
        ScanMode.BARCODE, // حالت اسکن
      );

      if (!mounted) return;

      if (barcode != '-1') {
        setState(() {
          _barcodeController.text = barcode;
        });
        _showSuccessMessage('بارکد اسکن شد ✅');
      }
    } catch (e) {
      _showSuccessMessage('خطا در اسکن بارکد ❌');
    }
  }

  // ==================== پیام موفقیت در وسط صفحه ====================
  
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
              color: message.contains('❌') || message.contains('خطا') 
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
                  message.contains('❌') || message.contains('خطا') 
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
                    fontSize: 16,
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

  // ==================== گزارش هوشمند ====================
  
  void _addSmartLog(String message) {
    setState(() {
      final timestamp = DateTime.now();
      final time = '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('پاک کردن گزارش هوشمند'),
        content: const Text('آیا از پاک کردن همه گزارش‌های هوشمند مطمئن هستید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('انصراف'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
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

  // ==================== جستجو ====================
  
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

      final currentResults = _currentItems.where((item) =>
        item.name.toLowerCase().contains(searchTerm) ||
        item.barcode.contains(searchTerm)
      ).toList();
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

  // ==================== افزودن کالا ====================
  
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
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
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
                // بارکد با دکمه دوربین
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _barcodeController,
                        decoration: InputDecoration(
                          labelText: 'شماره بارکد',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          hintText: 'اسکن یا دستی وارد کنید',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.camera_alt, color: Colors.blue, size: 30),
                      onPressed: _scanBarcode,
                      tooltip: 'اسکن بارکد با دوربین',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // نام کالا
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'نام کالا',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'لطفاً نام کالا را وارد کنید';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                // واحد سنجش
                Row(
                  children: [
                    const Text('واحد سنجش:'),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedUnit,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'عددی', child: Text('عددی')),
                          DropdownMenuItem(value: 'کیلویی', child: Text('کیلویی')),
                          DropdownMenuItem(value: 'بسته‌ای', child: Text('بسته‌ای')),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedUnit = value!;
                            _isPackageUnit = (value == 'بسته‌ای');
                            if (!_isPackageUnit) {
                              _packageSizeController.clear();
                            }
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // تعداد
                TextFormField(
                  controller: _quantityController,
                  decoration: InputDecoration(
                    labelText: 'تعداد (${_selectedUnit == 'بسته‌ای' ? 'بسته' : _selectedUnit})',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    hintText: _selectedUnit == 'بسته‌ای' ? 'تعداد بسته‌ها' : 'تعداد را وارد کنید',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'لطفاً تعداد را وارد کنید';
                    }
                    if (int.tryParse(value) == null) {
                      return 'لطفاً یک عدد معتبر وارد کنید';
                    }
                    return null;
                  },
                ),
                // باکس تعداد داخل بسته (فقط در حالت بسته‌ای - اختیاری)
                if (_isPackageUnit) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _packageSizeController,
                    decoration: InputDecoration(
                      labelText: 'تعداد داخل هر بسته (اختیاری)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      hintText: 'مثلاً 10 - در صورت وارد نکردن، فقط بسته ثبت می‌شود',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],
                const SizedBox(height: 12),
                // قیمت خرید
                TextFormField(
                  controller: _purchasePriceController,
                  decoration: const InputDecoration(
                    labelText: 'قیمت خرید (ریال)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixText: 'ریال ',
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    final formatted = _formatNumber(value);
                    if (formatted != value) {
                      _purchasePriceController.value = TextEditingValue(
                        text: formatted,
                        selection: TextSelection.collapsed(offset: formatted.length),
                      );
                    }
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'لطفاً قیمت خرید را وارد کنید';
                    }
                    final cleanValue = value.replaceAll(',', '');
                    if (int.tryParse(cleanValue) == null) {
                      return 'لطفاً یک عدد معتبر وارد کنید';
                    }
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
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                final newItem = DeliveryItem(
                  name: _nameController.text,
                  quantity: int.parse(_quantityController.text),
                  realQuantity: int.parse(_quantityController.text),
                  purchasePrice: _convertPrice(_purchasePriceController.text),
                  barcode: _barcodeController.text.isNotEmpty 
                      ? _barcodeController.text 
                      : DateTime.now().millisecondsSinceEpoch.toString(),
                  date: DateTime.now().millisecondsSinceEpoch.toString(),
                  unit: _selectedUnit,
                  packageSize: _packageSizeController.text.isNotEmpty 
                      ? int.parse(_packageSizeController.text) 
                      : 0,
                );
                
                if (targetManifest != null) {
                  setState(() {
                    targetManifest.items.add(newItem);
                    targetManifest.totalPrice += newItem.purchasePrice * newItem.realQuantity;
                  });
                  _addSmartLog('➕ کالا "${newItem.name}" به بارنامه شماره ${targetManifest.number} اضافه شد');
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
                  _addSmartLog('✅ کالا "${_nameController.text}" با تعداد ${newItem.quantity} اضافه شد');
                  _clearControllers();
                  Navigator.pop(context);
                  _showSuccessMessage('کالا اضافه شد ✅');
                }
              }
            },
            child: const Text('افزودن'),
          ),
        ],
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

  // ==================== ثبت بارنامه ====================
  
  void _submitDelivery() async {
    final TextEditingController dateController = TextEditingController();
    dateController.text = _getTodayDate();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'ثبت نهایی تحویل بار',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('لطفاً تاریخ بارنامه را وارد کنید:'),
            const SizedBox(height: 16),
            TextFormField(
              controller: dateController,
              decoration: InputDecoration(
                labelText: 'تاریخ (مثلاً ۱۴۰۴/۰۵/۱۵)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.calendar_today),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green.shade50, Colors.green.shade100],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'تعداد کالاها: ${_currentItems.length}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'مجموع قیمت: ${_displayPrice(_totalPurchasePrice)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'شماره بارنامه: ${_getNextManifestNumber()}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('انصراف'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
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
              
              _addSmartLog('📋 بارنامه شماره ${manifest.number} با ${manifest.items.length} کالا ثبت شد');
              
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

  // ==================== ذخیره و بارگذاری ====================
  
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
    setState(() {
      _isLoading = true;
    });

    final prefs = await SharedPreferences.getInstance();
    final manifestsJson = prefs.getString('delivery_manifests');

    if (manifestsJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(manifestsJson);
        setState(() {
          _savedManifests = decoded.map((item) => DeliveryManifest.fromJson(item)).toList();
          _isLoading = false;
        });
      } catch (e) {
        setState(() {
          _isLoading = false;
        });
      }
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // ==================== ویرایش بارنامه ====================
  
  void _startEditingManifest(DeliveryManifest manifest) {
    final dateController = TextEditingController(text: manifest.date);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          'ویرایش بارنامه شماره ${manifest.number}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: StatefulBuilder(
          builder: (context, setStateDialog) {
            return SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: dateController,
                    decoration: InputDecoration(
                      labelText: 'تاریخ بارنامه',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.edit_calendar),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'لیست کالاها:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: Colors.green),
                        onPressed: () {
                          Navigator.pop(context);
                          _showAddDialog(targetManifest: manifest);
                        },
                        tooltip: 'افزودن کالا',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 200,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: manifest.items.length,
                      itemBuilder: (context, index) {
                        final item = manifest.items[index];
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: Colors.blue.shade100,
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                          title: Text(
                            item.name, 
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          subtitle: Text(
                            'تعداد: ${item.quantity} | ${_displayPrice(item.purchasePrice)}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                            onPressed: () {
                              setState(() {
                                final removedItem = manifest.items[index];
                                manifest.items.removeAt(index);
                                manifest.totalPrice -= removedItem.purchasePrice * removedItem.realQuantity;
                              });
                              setStateDialog(() {});
                              _addSmartLog('❌ کالا "${item.name}" از بارنامه شماره ${manifest.number} حذف شد');
                              _saveManifestChanges(manifest);
                              _showSuccessMessage('کالا حذف شد ❌');
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
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('انصراف'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () async {
              final oldDate = manifest.date;
              final newDate = dateController.text;
              
              setState(() {
                manifest.date = newDate;
              });
              
              await _saveManifestChanges(manifest);
              
              if (oldDate != newDate) {
                _addSmartLog('📅 تاریخ بارنامه شماره ${manifest.number} از $oldDate به $newDate تغییر یافت');
              }
              
              Navigator.pop(context);
              _showSuccessMessage('تغییرات ذخیره شد ✅');
            },
            child: const Text('ذخیره تغییرات'),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text('حذف بارنامه شماره ${manifest.number}'),
        content: Text('آیا از حذف بارنامه تاریخ ${manifest.date} مطمئن هستید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('انصراف'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () async {
              setState(() {
                _savedManifests.remove(manifest);
              });
              
              final prefs = await SharedPreferences.getInstance();
              final manifestsJson = _savedManifests.map((m) => m.toJson()).toList();
              await prefs.setString('delivery_manifests', jsonEncode(manifestsJson));
              
              _addSmartLog('🗑️ بارنامه شماره ${manifest.number} حذف شد');
              
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text('لغو عملیات'),
        content: const Text('آیا از لغو این محموله مطمئن هستید؟\nهمه کالاها حذف خواهند شد.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('انصراف'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              setState(() {
                _currentItems.clear();
                _filteredItems.clear();
                _searchController.clear();
                _isSearching = false;
              });
              _addSmartLog('❌ محموله لغو شد');
              Navigator.pop(context);
              _showSuccessMessage('محموله لغو شد ❌');
            },
            child: const Text('بله، لغو شود'),
          ),
        ],
      ),
    );
  }

  // ==================== ویجت‌های نمایشی ====================
  
  Widget _buildSmartLogs() {
    if (_smartLogs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.info_outline, size: 40, color: Colors.grey.shade400),
              const SizedBox(height: 8),
              Text(
                'هیچ گزارشی موجود نیست',
                style: TextStyle(color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      );
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '📊 گزارش هوشمند:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: _clearSmartLogs,
              tooltip: 'پاک کردن گزارش‌ها',
            ),
          ],
        ),
        Container(
          height: 120,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: ListView.builder(
            reverse: true,
            shrinkWrap: true,
            itemCount: _smartLogs.length,
            itemBuilder: (context, index) {
              final log = _smartLogs[index];
              final isSuccess = log.contains('✅');
              final isError = log.contains('❌') || log.contains('🗑️');
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  log,
                  style: TextStyle(
                    fontSize: 12,
                    color: isSuccess ? Colors.green.shade700 
                        : isError ? Colors.red.shade700 
                        : Colors.black87,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSearchResults() {
    if (!_isSearching) return const SizedBox.shrink();
    
    final totalResults = _filteredItems.length + _manifestSearchResults.length;
    
    if (totalResults == 0) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.search_off, size: 60, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                '🔍 جستجوی پیشرفته: هیچ کالایی با این نام یا بارکد پیدا نشد',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
              Text(
                'کلمات کلیدی را تغییر دهید یا بارکد را بررسی کنید',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      );
    }
    
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '🔍 جستجوی پیشرفته: $totalResults نتیجه پیدا شد',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Colors.blue,
              ),
            ),
          ),
          
          if (_filteredItems.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '📦 کالاهای موجود:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
            ..._filteredItems.map((item) => _buildSearchResultItem(item, null)),
          ],
          
          if (_manifestSearchResults.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '📋 بارنامه‌های ذخیره شده:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
            ..._manifestSearchResults.map((result) => 
              _buildManifestSearchResult(result['manifest'], result['item'])
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchResultItem(DeliveryItem item, DeliveryManifest? manifest) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: Colors.blue.shade700, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'تعداد: ${item.quantity} ${item.packageSize > 0 ? '(مجموع: ${item.realQuantity})' : ''}',
            style: const TextStyle(fontSize: 13),
          ),
          Text(
            'قیمت: ${_displayPrice(item.purchasePrice)}',
            style: const TextStyle(fontSize: 13),
          ),
          if (manifest != null)
            Text(
              '📍 بارنامه شماره ${manifest.number} - تاریخ: ${manifest.date}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
        ],
      ),
    );
  }

  Widget _buildManifestSearchResult(DeliveryManifest manifest, DeliveryItem item) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.description, color: Colors.green.shade700, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'بارنامه شماره ${manifest.number}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.label, size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Text(
                '📌 ${item.name}',
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
          Text(
            'تعداد: ${item.quantity}',
            style: const TextStyle(fontSize: 13),
          ),
          Text(
            '📅 تاریخ: ${manifest.date}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
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
            decoration: InputDecoration(
              labelText: '🔍 جستجوی پیشرفته در بارنامه‌ها',
              hintText: 'نام یا بارکد کالا را وارد کنید...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
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
          Expanded(
            child: _buildSearchResults(),
          )
        else
          Expanded(
            child: _currentItems.isEmpty && _savedManifests.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          'هیچ کالا یا بارنامه‌ای وجود ندارد',
                          style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'برای شروع، روی دکمه + کلیک کنید',
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                        ),
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
                        // کلیک روی بارنامه برای ورود (بدون نیاز به ایموجی چشم)
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
        leading: CircleAvatar(
          backgroundColor: Colors.blue.shade100,
          child: Text(
            '${(index + 1)}',
            style: TextStyle(color: Colors.blue.shade700),
          ),
        ),
        title: Text(
          item.name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.barcode.isNotEmpty)
              Text('بارکد: ${item.barcode}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            Text('واحد: ${item.unit}', style: const TextStyle(fontSize: 13)),
            Text('تعداد: ${item.quantity}${item.packageSize > 0 ? ' (مجموع: ${item.realQuantity})' : ''}'),
            Text('قیمت خرید: ${_displayPrice(item.purchasePrice)}'),
            Text(
              'مجموع: ${_displayPrice(item.purchasePrice * item.realQuantity)}',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
            ),
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
        leading: CircleAvatar(
          backgroundColor: Colors.green.shade100,
          child: Text(
            '${manifest.number}',
            style: TextStyle(color: Colors.green.shade700),
          ),
        ),
        title: Text(
          'بارنامه شماره ${manifest.number}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('تاریخ: ${manifest.date}'),
            Text('تعداد کالاها: ${manifest.items.length}'),
            Text('مجموع: ${_displayPrice(manifest.totalPrice)}'),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: Colors.orange),
              onPressed: () => _startEditingManifest(manifest),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () => _deleteManifest(manifest),
            ),
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
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('مجموع قیمت خرید:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text(
                  _displayPrice(_totalPurchasePrice),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 2,
                  ),
                  onPressed: _cancelDelivery,
                  child: const Text(
                    'لغو',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 2,
                  ),
                  onPressed: _submitDelivery,
                  child: const Text(
                    'ثبت نهایی',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
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
            gradient: LinearGradient(
              colors: [Colors.blue.shade50, Colors.blue.shade100],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('شماره بارنامه:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('${manifest.number}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('تاریخ:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(manifest.date),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('تعداد کالاها:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('${manifest.items.length}'),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('مجموع قیمت:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(_displayPrice(manifest.totalPrice), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: manifest.items.length,
            itemBuilder: (context, index) {
              final item = manifest.items[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue.shade100,
                    child: Text('${index + 1}', style: TextStyle(color: Colors.blue.shade700)),
                  ),
                  title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('تعداد: ${item.quantity}${item.packageSize > 0 ? ' (مجموع: ${item.realQuantity})' : ''}'),
                      Text('قیمت: ${_displayPrice(item.purchasePrice)}'),
                      Text('مجموع: ${_displayPrice(item.purchasePrice * item.realQuantity)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isViewingManifest && _currentItems.isEmpty,
      onPopInvoked: (didPop) {
        if (!didPop) {
          if (_isViewingManifest) {
            _goBackToMain();
          } else if (_currentItems.isNotEmpty) {
            _cancelDelivery();
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _isViewingManifest 
                ? 'بارنامه شماره ${_viewingManifest!.number}' 
                : '📦 برنامه تحویل بار',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          elevation: 0,
          actions: [
            if (!_isViewingManifest) ...[
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'افزودن کالا',
                onPressed: () => _showAddDialog(),
              ),
            ],
            if (_isViewingManifest) ...[
              IconButton(
                icon: const Icon(Icons.edit_outlined, color: Colors.orange),
                onPressed: () => _startEditingManifest(_viewingManifest!),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => _deleteManifest(_viewingManifest!),
              ),
            ],
          ],
          leading: _isViewingManifest 
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _goBackToMain,
                )
              : null,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _isViewingManifest
                ? _buildManifestView()
                : _buildMainView(),
      ),
    );
  }
}

// ==================== مدل‌های داده ====================

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
