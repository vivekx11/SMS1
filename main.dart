// main.dart
// Big monolithic blueprint for Mobile Repair All-in-One app.
// Contains: DB (sqflite), Khata ledger, Repair tracking (with image), Inventory,
// Customer DB, Billing (PDF placeholder), Password store (secure storage),
// SMS sending (telephony), Analytics (basic), Backup/export (CSV), provider state.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:excel/excel.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:telephony/telephony.dart';
import 'package:file_picker/file_picker.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDatabase.init();
  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AppState(db))],
      child: MyRepairShopApp(),
    ),
  );
}

class MyRepairShopApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mobile Repair All-in-One',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.deepPurple, useMaterial3: true),
      home: MainHomeScreen(),
    );
  }
}

/////////////////////
// App State & DB  //
/////////////////////

class AppState extends ChangeNotifier {
  final AppDatabase db;
  List<KhataEntry> khata = [];
  List<RepairJob> repairs = [];
  List<InventoryItem> items = [];
  List<Customer> customers = [];
  List<SmsLog> smsLogs = [];

  AppState(this.db) {
    _loadAll();
  }

  Future<void> _loadAll() async {
    khata = await db.getKhataEntries();
    repairs = await db.getRepairs();
    items = await db.getInventoryItems();
    customers = await db.getCustomers();
    smsLogs = await db.getSmsLogs();
    notifyListeners();
  }

  Future<void> addKhata(KhataEntry e) async {
    await db.insertKhata(e);
    khata = await db.getKhataEntries();
    notifyListeners();
  }

  Future<void> addRepair(RepairJob r) async {
    await db.insertRepair(r);
    repairs = await db.getRepairs();
    notifyListeners();
  }

  Future<void> addItem(InventoryItem it) async {
    await db.insertInventoryItem(it);
    items = await db.getInventoryItems();
    notifyListeners();
  }

  Future<void> addCustomer(Customer c) async {
    await db.insertCustomer(c);
    customers = await db.getCustomers();
    notifyListeners();
  }

  Future<void> addSmsLog(SmsLog s) async {
    await db.insertSmsLog(s);
    smsLogs = await db.getSmsLogs();
    notifyListeners();
  }
}

// Database wrapper (sqflite)
class AppDatabase {
  static Database? _db;
  Database get db {
    if (_db == null) {
      throw Exception("Database not initialized!");
    }
    return _db!;
  }

  static Future<AppDatabase> init() async {
    final instance = AppDatabase();
    await instance._initDb();
    return instance;
  }

  Future<void> _initDb() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = p.join(documentsDirectory.path, "app_data.db");
    _db = await openDatabase(path, version: 1, onCreate: _onCreate);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE khata (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        amount REAL,
        type TEXT,
        note TEXT,
        timestamp INTEGER
      );
    ''');

    await db.execute('''
      CREATE TABLE repairs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customerName TEXT,
        phone TEXT,
        model TEXT,
        imei TEXT,
        problem TEXT,
        status TEXT,
        imagePath TEXT,
        createdAt INTEGER
      );
    ''');

    await db.execute('''
      CREATE TABLE inventory (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        qty INTEGER,
        buyPrice REAL,
        sellPrice REAL
      );
    ''');

    await db.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        phone TEXT,
        address TEXT,
        note TEXT
      );
    ''');

    await db.execute('''
      CREATE TABLE sms_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        toNumber TEXT,
        message TEXT,
        sentAt INTEGER,
        status TEXT
      );
    ''');
  }

  // Khata
  Future<int> insertKhata(KhataEntry e) => _db!.insert('khata', e.toMap());
  Future<List<KhataEntry>> getKhataEntries() async {
    final rows = await _db!.query('khata', orderBy: 'timestamp DESC');
    return rows.map((r) => KhataEntry.fromMap(r)).toList();
  }

  // Repairs
  Future<int> insertRepair(RepairJob r) => _db!.insert('repairs', r.toMap());
  Future<List<RepairJob>> getRepairs() async {
    final rows = await _db!.query('repairs', orderBy: 'createdAt DESC');
    return rows.map((r) => RepairJob.fromMap(r)).toList();
  }

  // Inventory
  Future<int> insertInventoryItem(InventoryItem i) =>
      _db!.insert('inventory', i.toMap());
  Future<List<InventoryItem>> getInventoryItems() async {
    final rows = await _db!.query('inventory', orderBy: 'id DESC');
    return rows.map((r) => InventoryItem.fromMap(r)).toList();
  }

  // Customers
  Future<int> insertCustomer(Customer c) => _db!.insert('customers', c.toMap());
  Future<List<Customer>> getCustomers() async {
    final rows = await _db!.query('customers', orderBy: 'id DESC');
    return rows.map((r) => Customer.fromMap(r)).toList();
  }

  // SMS logs
  Future<int> insertSmsLog(SmsLog s) => _db!.insert('sms_logs', s.toMap());
  Future<List<SmsLog>> getSmsLogs() async {
    final rows = await _db!.query('sms_logs', orderBy: 'sentAt DESC');
    return rows.map((r) => SmsLog.fromMap(r)).toList();
  }
}

//////////////////////
// Data Models      //
//////////////////////

class KhataEntry {
  int? id;
  String title;
  double amount;
  String type; // income/expense
  String note;
  int timestamp;
  KhataEntry({
    this.id,
    required this.title,
    required this.amount,
    required this.type,
    this.note = '',
    int? timestamp,
  }) : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;
  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'amount': amount,
    'type': type,
    'note': note,
    'timestamp': timestamp,
  };
  factory KhataEntry.fromMap(Map<String, dynamic> m) => KhataEntry(
    id: m['id'],
    title: m['title'],
    amount: (m['amount'] as num).toDouble(),
    type: m['type'],
    note: m['note'] ?? '',
    timestamp: m['timestamp'],
  );
}

class RepairJob {
  int? id;
  String customerName;
  String phone;
  String model;
  String imei;
  String problem;
  String status;
  String? imagePath;
  int createdAt;
  RepairJob({
    this.id,
    required this.customerName,
    required this.phone,
    required this.model,
    required this.imei,
    required this.problem,
    this.status = 'Pending',
    this.imagePath,
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toMap() => {
    'id': id,
    'customerName': customerName,
    'phone': phone,
    'model': model,
    'imei': imei,
    'problem': problem,
    'status': status,
    'imagePath': imagePath,
    'createdAt': createdAt,
  };

  factory RepairJob.fromMap(Map<String, dynamic> m) => RepairJob(
    id: m['id'],
    customerName: m['customerName'],
    phone: m['phone'],
    model: m['model'],
    imei: m['imei'],
    problem: m['problem'],
    status: m['status'],
    imagePath: m['imagePath'],
    createdAt: m['createdAt'],
  );
}

class InventoryItem {
  int? id;
  String name;
  int qty;
  double buyPrice;
  double sellPrice;
  InventoryItem({
    this.id,
    required this.name,
    this.qty = 0,
    this.buyPrice = 0.0,
    this.sellPrice = 0.0,
  });
  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'qty': qty,
    'buyPrice': buyPrice,
    'sellPrice': sellPrice,
  };
  factory InventoryItem.fromMap(Map<String, dynamic> m) => InventoryItem(
    id: m['id'],
    name: m['name'],
    qty: m['qty'],
    buyPrice: (m['buyPrice'] as num).toDouble(),
    sellPrice: (m['sellPrice'] as num).toDouble(),
  );
}

class Customer {
  int? id;
  String name;
  String phone;
  String address;
  String note;
  Customer({
    this.id,
    required this.name,
    required this.phone,
    this.address = '',
    this.note = '',
  });
  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'phone': phone,
    'address': address,
    'note': note,
  };
  factory Customer.fromMap(Map<String, dynamic> m) => Customer(
    id: m['id'],
    name: m['name'],
    phone: m['phone'],
    address: m['address'] ?? '',
    note: m['note'] ?? '',
  );
}

class SmsLog {
  int? id;
  String toNumber;
  String message;
  int sentAt;
  String status;

  SmsLog({
    this.id,
    required this.toNumber,
    required this.message,
    int? sentAt, // ← FIXED
    this.status = 'sent',
  }) : sentAt = (sentAt == null || sentAt == 0)
           ? DateTime.now().millisecondsSinceEpoch
           : sentAt;

  Map<String, dynamic> toMap() => {
    'id': id,
    'toNumber': toNumber,
    'message': message,
    'sentAt': sentAt,
    'status': status,
  };

  factory SmsLog.fromMap(Map<String, dynamic> m) => SmsLog(
    id: m['id'],
    toNumber: m['toNumber'],
    message: m['message'],
    sentAt: m['sentAt'],
    status: m['status'],
  );
}

//////////////////////
// Utility Services //
//////////////////////

final _secureStorage = FlutterSecureStorage();
final telephony = Telephony.instance;

// Password store helpers
Future<void> secureSave(String key, String value) =>
    _secureStorage.write(key: key, value: value);
Future<String?> secureRead(String key) => _secureStorage.read(key: key);
Future<void> secureDelete(String key) => _secureStorage.delete(key: key);

// Image picker helper
final ImagePicker _picker = ImagePicker();
Future<String?> pickImageAndSave() async {
  final xfile = await _picker.pickImage(
    source: ImageSource.camera,
    imageQuality: 70,
  );
  if (xfile == null) return null;
  final doc = await getApplicationDocumentsDirectory();
  final file = File(xfile.path);
  final newPath = p.join(doc.path, 'images', p.basename(xfile.path));
  await Directory(p.join(doc.path, 'images')).create(recursive: true);
  final saved = await file.copy(newPath);
  return saved.path;
}

// CSV export for Khata
Future<String> exportKhataCsv(List<KhataEntry> list) async {
  final doc = await getApplicationDocumentsDirectory();
  final file = File(p.join(doc.path, 'khata_export.csv'));
  final sb = StringBuffer();
  sb.writeln('title,amount,type,note,timestamp');
  for (final e in list) {
    sb.writeln(
      '"${e.title.replaceAll('"', '""')}",${e.amount},${e.type},"${e.note.replaceAll('"', '""')}",${DateTime.fromMillisecondsSinceEpoch(e.timestamp)}',
    );
  }
  await file.writeAsString(sb.toString());
  return file.path;
}

// Basic PDF invoice (uses printing package)
Future<Uint8List> generateInvoicePdf(RepairJob job, Customer? cust) async {
  final pdf = pw.Document();
  pdf.addPage(
    pw.Page(
      build: (pw.Context ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Repair Invoice', style: pw.TextStyle(fontSize: 24)),
          pw.SizedBox(height: 10),
          pw.Text('Customer: ${cust?.name ?? job.customerName}'),
          pw.Text('Phone: ${job.phone}'),
          pw.Text('Model: ${job.model}'),
          pw.SizedBox(height: 10),
          pw.Text('Problem: ${job.problem}'),
          pw.SizedBox(height: 20),
          pw.Text('Thank you for your business.'),
        ],
      ),
    ),
  );
  return pdf.save();
}

//////////////////////
// UI - Main Screen //
//////////////////////

class MainHomeScreen extends StatefulWidget {
  @override
  _MainHomeScreenState createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    DashboardPage(),
    KhataPage(),
    RepairTrackingPage(),
    InventoryPage(),
    SmsSenderPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Mobile Repair Shop Manager")),
      drawer: AppDrawer(
        onNavigate: (index) {
          setState(() => _selectedIndex = index);
          Navigator.pop(context);
        },
      ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.deepPurple,
        unselectedItemColor: Colors.grey,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.book), label: "Khata"),
          BottomNavigationBarItem(icon: Icon(Icons.build), label: "Repair"),
          BottomNavigationBarItem(icon: Icon(Icons.inventory), label: "Stock"),
          BottomNavigationBarItem(icon: Icon(Icons.sms), label: "SMS"),
        ],
      ),
    );
  }
}

class AppDrawer extends StatelessWidget {
  final void Function(int) onNavigate;
  AppDrawer({required this.onNavigate});
  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Colors.deepPurple),
            child: Text(
              "All In One Shop Manager",
              style: TextStyle(color: Colors.white, fontSize: 22),
            ),
          ),
          _dItem("Dashboard", 0, context),
          _dItem("Daily Khata", 1, context),
          _dItem("Repair Tracking", 2, context),
          _dItem("Inventory / Stock", 3, context),
          _dItem("SMS Sender", 4, context),
          const Divider(),
          ListTile(
            title: const Text("Customer Database"),
            leading: const Icon(Icons.people),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => CustomerDatabasePage()),
            ),
          ),
          ListTile(
            title: const Text("Password Store"),
            leading: const Icon(Icons.lock),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => PasswordStorePage()),
            ),
          ),
          ListTile(
            title: const Text("Billing / Invoice"),
            leading: const Icon(Icons.receipt_long),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => BillingPage()),
            ),
          ),
          ListTile(
            title: const Text("Warranty Tracker"),
            leading: const Icon(Icons.verified),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => WarrantyPage()),
            ),
          ),
          ListTile(
            title: const Text("Analytics"),
            leading: const Icon(Icons.bar_chart),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AnalyticsPage()),
            ),
          ),
          ListTile(
            title: const Text("Settings"),
            leading: const Icon(Icons.settings),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SettingsPage()),
            ),
          ),
        ],
      ),
    );
  }

  ListTile _dItem(String title, int idx, BuildContext context) {
    return ListTile(
      title: Text(title),
      leading: const Icon(Icons.arrow_right),
      onTap: () {
        onNavigate(idx);
      },
    );
  }
}

/////////////////////////
// Dashboard & Pages   //
/////////////////////////

class DashboardPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final st = Provider.of<AppState>(context);
    final totalIncome = st.khata
        .where((e) => e.type == 'income')
        .fold<double>(0, (p, e) => p + e.amount);
    final totalExpense = st.khata
        .where((e) => e.type == 'expense')
        .fold<double>(0, (p, e) => p + e.amount);
    final pendingRepairs = st.repairs
        .where((r) => r.status != 'Completed')
        .length;
    final completed = st.repairs.where((r) => r.status == 'Completed').length;

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: ListView(
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_balance_wallet),
              title: const Text("Today's Income"),
              subtitle: Text("₹${totalIncome.toStringAsFixed(2)}"),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.money_off),
              title: const Text("Today's Expense"),
              subtitle: Text("₹${totalExpense.toStringAsFixed(2)}"),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.build_circle),
              title: const Text("Repairs Pending"),
              subtitle: Text("$pendingRepairs pending"),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.check_circle),
              title: const Text("Repairs Completed"),
              subtitle: Text("$completed completed"),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            icon: const Icon(Icons.file_download),
            label: const Text("Export Khata (CSV)"),
            onPressed: () async {
              final path = await exportKhataCsv(st.khata);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text("Exported to $path")));
            },
          ),
        ],
      ),
    );
  }
}

class KhataPage extends StatefulWidget {
  @override
  _KhataPageState createState() => _KhataPageState();
}

class _KhataPageState extends State<KhataPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  String _type = 'income';
  final TextEditingController _note = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final st = Provider.of<AppState>(context);
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        children: [
          Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                TextFormField(
                  controller: _amount,
                  decoration: const InputDecoration(labelText: 'Amount'),
                  keyboardType: TextInputType.number,
                ),
                DropdownButtonFormField(
                  value: _type,
                  items: const [
                    DropdownMenuItem(child: Text('Income'), value: 'income'),
                    DropdownMenuItem(child: Text('Expense'), value: 'expense'),
                  ],
                  onChanged: (p0) => setState(() => _type = p0 as String),
                ),
                TextFormField(
                  controller: _note,
                  decoration: const InputDecoration(labelText: 'Note'),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () async {
                    if (_amount.text.trim().isEmpty) return;
                    final entry = KhataEntry(
                      title: _title.text.trim(),
                      amount: double.tryParse(_amount.text) ?? 0.0,
                      type: _type,
                      note: _note.text.trim(),
                    );
                    await st.addKhata(entry);
                    _title.clear();
                    _amount.clear();
                    _note.clear();
                  },
                  child: const Text('Add Entry'),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
          const Divider(),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: st.khata.length,
              itemBuilder: (_, idx) {
                final e = st.khata[idx];
                return ListTile(
                  leading: Icon(
                    e.type == 'income' ? Icons.add : Icons.remove,
                    color: e.type == 'income' ? Colors.green : Colors.red,
                  ),
                  title: Text(e.title),
                  subtitle: Text(
                    "${e.note}\n${DateTime.fromMillisecondsSinceEpoch(e.timestamp)}",
                  ),
                  trailing: Text("₹${e.amount.toStringAsFixed(2)}"),
                  isThreeLine: true,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class RepairTrackingPage extends StatefulWidget {
  @override
  _RepairTrackingPageState createState() => _RepairTrackingPageState();
}

class _RepairTrackingPageState extends State<RepairTrackingPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _cname = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _model = TextEditingController();
  final TextEditingController _imei = TextEditingController();
  final TextEditingController _problem = TextEditingController();
  String? _imagePath;

  @override
  Widget build(BuildContext context) {
    final st = Provider.of<AppState>(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _cname,
                  decoration: const InputDecoration(labelText: 'Customer Name'),
                ),
                TextFormField(
                  controller: _phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                  keyboardType: TextInputType.phone,
                ),
                TextFormField(
                  controller: _model,
                  decoration: const InputDecoration(labelText: 'Model'),
                ),
                TextFormField(
                  controller: _imei,
                  decoration: const InputDecoration(labelText: 'IMEI'),
                ),
                TextFormField(
                  controller: _problem,
                  decoration: const InputDecoration(labelText: 'Problem'),
                ),
                const SizedBox(height: 8),
                if (_imagePath != null)
                  Image.file(File(_imagePath!), height: 120),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () async {
                        final p = await pickImageAndSave();
                        if (p != null) setState(() => _imagePath = p);
                      },
                      icon: const Icon(Icons.camera_alt),
                      label: const Text("Add Photo"),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () async {
                        if (_cname.text.trim().isEmpty ||
                            _phone.text.trim().isEmpty)
                          return;
                        final job = RepairJob(
                          customerName: _cname.text.trim(),
                          phone: _phone.text.trim(),
                          model: _model.text.trim(),
                          imei: _imei.text.trim(),
                          problem: _problem.text.trim(),
                          imagePath: _imagePath,
                        );
                        await st.addRepair(job);
                        _cname.clear();
                        _phone.clear();
                        _model.clear();
                        _imei.clear();
                        _problem.clear();
                        setState(() => _imagePath = null);
                      },
                      icon: const Icon(Icons.save),
                      label: const Text("Save Repair"),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: st.repairs.length,
              itemBuilder: (_, idx) {
                final r = st.repairs[idx];
                return Card(
                  child: ListTile(
                    leading: r.imagePath != null
                        ? Image.file(
                            File(r.imagePath!),
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                          )
                        : const Icon(Icons.phone_android),
                    title: Text("${r.customerName} • ${r.model}"),
                    subtitle: Text("${r.problem}\nStatus: ${r.status}"),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'Complete') {
                          r.status = 'Completed';
                          await st.db.db.update(
                            'repairs',
                            r.toMap(),
                            where: 'id=?',
                            whereArgs: [r.id],
                          );
                          st.repairs = await st.db.getRepairs();
                          st.notifyListeners();
                        } else if (v == 'Invoice') {
                          final cust = (await st.db.getCustomers()).firstWhere(
                            (c) => c.phone == r.phone,
                            orElse: () =>
                                Customer(name: r.customerName, phone: r.phone),
                          );
                          final bytes = await generateInvoicePdf(r, cust);
                          await Printing.layoutPdf(onLayout: (_) => bytes);
                        } else if (v == 'Call') {
                          final uri = Uri.parse('tel:${r.phone}');
                          if (await canLaunchUrl(uri)) await launchUrl(uri);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'Complete',
                          child: Text('Mark Complete'),
                        ),
                        PopupMenuItem(
                          value: 'Invoice',
                          child: Text('Generate Invoice'),
                        ),
                        PopupMenuItem(
                          value: 'Call',
                          child: Text('Call Customer'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class InventoryPage extends StatefulWidget {
  @override
  _InventoryPageState createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final _name = TextEditingController();
  final _qty = TextEditingController(text: '0');
  final _buy = TextEditingController(text: '0');
  final _sell = TextEditingController(text: '0');

  @override
  Widget build(BuildContext context) {
    final st = Provider.of<AppState>(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Item Name'),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _qty,
                  decoration: const InputDecoration(labelText: 'Qty'),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _buy,
                  decoration: const InputDecoration(labelText: 'Buy Price'),
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _sell,
                  decoration: const InputDecoration(labelText: 'Sell Price'),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () async {
                  if (_name.text.trim().isEmpty) return;
                  final it = InventoryItem(
                    name: _name.text.trim(),
                    qty: int.tryParse(_qty.text) ?? 0,
                    buyPrice: double.tryParse(_buy.text) ?? 0.0,
                    sellPrice: double.tryParse(_sell.text) ?? 0.0,
                  );
                  await st.addItem(it);
                  _name.clear();
                  _qty.text = '0';
                  _buy.text = '0';
                  _sell.text = '0';
                },
                child: const Text('Add Item'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: st.items.length,
              itemBuilder: (_, idx) {
                final it = st.items[idx];
                return ListTile(
                  title: Text(it.name),
                  subtitle: Text(
                    'Qty: ${it.qty} • Buy: ₹${it.buyPrice} • Sell: ₹${it.sellPrice}',
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class SmsSenderPage extends StatefulWidget {
  @override
  _SmsSenderPageState createState() => _SmsSenderPageState();
}

class _SmsSenderPageState extends State<SmsSenderPage> {
  final _to = TextEditingController();
  final _msg = TextEditingController();
  bool _sending = false;

  Future<void> _sendSms(AppState st) async {
    final to = _to.text.trim();
    final message = _msg.text.trim();
    if (to.isEmpty || message.isEmpty) return;
    setState(() => _sending = true);

    // request permissions
    final permissionsGranted = await telephony.requestSmsPermissions;
    if (permissionsGranted != true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("SMS permission denied")));
      setState(() => _sending = false);
      return;
    }

    try {
      await telephony.sendSms(to: to, message: message);
      final log = SmsLog(toNumber: to, message: message, status: 'sent');
      await st.addSmsLog(log);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("SMS sent")));
      _to.clear();
      _msg.clear();
    } catch (e) {
      final log = SmsLog(toNumber: to, message: message, status: 'failed');
      await st.addSmsLog(log);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to send: $e")));
    } finally {
      setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = Provider.of<AppState>(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          TextField(
            controller: _to,
            decoration: const InputDecoration(labelText: 'Recipient (+91...)'),
            keyboardType: TextInputType.phone,
          ),
          TextField(
            controller: _msg,
            decoration: const InputDecoration(labelText: 'Message'),
            maxLines: 4,
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _sending ? null : () => _sendSms(st),
            icon: const Icon(Icons.send),
            label: const Text('Send SMS'),
          ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 12),
          const Text(
            "SMS History",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: st.smsLogs.length,
              itemBuilder: (_, idx) {
                final s = st.smsLogs[idx];
                return ListTile(
                  title: Text(s.toNumber),
                  subtitle: Text(
                    "${s.message}\n${DateTime.fromMillisecondsSinceEpoch(s.sentAt)}",
                  ),
                  trailing: Text(s.status),
                  isThreeLine: true,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/////////////////////////
// Other Pages         //
/////////////////////////

class CustomerDatabasePage extends StatefulWidget {
  @override
  _CustomerDatabasePageState createState() => _CustomerDatabasePageState();
}

class _CustomerDatabasePageState extends State<CustomerDatabasePage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _addr = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final st = Provider.of<AppState>(context);
    return Scaffold(
      appBar: AppBar(title: const Text("Customer Database")),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: _phone,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
            TextField(
              controller: _addr,
              decoration: const InputDecoration(labelText: 'Address'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () async {
                if (_name.text.trim().isEmpty || _phone.text.trim().isEmpty)
                  return;
                final c = Customer(
                  name: _name.text.trim(),
                  phone: _phone.text.trim(),
                  address: _addr.text.trim(),
                );
                await st.addCustomer(c);
                _name.clear();
                _phone.clear();
                _addr.clear();
              },
              child: const Text('Add Customer'),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: st.customers.length,
                itemBuilder: (_, idx) {
                  final c = st.customers[idx];
                  return ListTile(
                    title: Text(c.name),
                    subtitle: Text('${c.phone}\n${c.address}'),
                    isThreeLine: true,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PasswordStorePage extends StatefulWidget {
  @override
  _PasswordStorePageState createState() => _PasswordStorePageState();
}

class _PasswordStorePageState extends State<PasswordStorePage> {
  final _keyCtrl = TextEditingController();
  final _valueCtrl = TextEditingController();
  List<MapEntry<String, String>> entries = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final all = await _secureStorage.readAll();
    setState(
      () => entries = all.entries.map((e) => MapEntry(e.key, e.value)).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Password Store')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: _keyCtrl,
              decoration: const InputDecoration(
                labelText: 'Label (eg: Google account)',
              ),
            ),
            TextField(
              controller: _valueCtrl,
              decoration: const InputDecoration(labelText: 'Password / PIN'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () async {
                if (_keyCtrl.text.trim().isEmpty ||
                    _valueCtrl.text.trim().isEmpty)
                  return;
                await secureSave(_keyCtrl.text.trim(), _valueCtrl.text.trim());
                _keyCtrl.clear();
                _valueCtrl.clear();
                await _loadAll();
              },
              child: const Text('Save'),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: entries.length,
                itemBuilder: (_, idx) {
                  final e = entries[idx];
                  return ListTile(
                    title: Text(e.key),
                    subtitle: Text(e.value),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () async {
                        await secureDelete(e.key);
                        await _loadAll();
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BillingPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final st = Provider.of<AppState>(context, listen: false);
    return Scaffold(
      appBar: AppBar(title: const Text("Billing / Invoice")),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            const Text(
              "Open a repair and use the popup menu -> Invoice to create a PDF invoice.",
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () async {
                // simple demo: generate invoice for last repair
                final repairs = st.repairs;
                if (repairs.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No repair found')),
                  );
                  return;
                }
                final last = repairs.first;
                final cust = (await st.db.getCustomers()).firstWhere(
                  (c) => c.phone == last.phone,
                  orElse: () =>
                      Customer(name: last.customerName, phone: last.phone),
                );
                final bytes = await generateInvoicePdf(last, cust);
                await Printing.layoutPdf(onLayout: (_) => bytes);
              },
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Generate PDF for last repair'),
            ),
          ],
        ),
      ),
    );
  }
}

class WarrantyPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // For demo, warranty info is taken from repairs age
    final st = Provider.of<AppState>(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Warranty Tracker')),
      body: ListView.builder(
        itemCount: st.repairs.length,
        itemBuilder: (_, idx) {
          final r = st.repairs[idx];
          final created = DateTime.fromMillisecondsSinceEpoch(r.createdAt);
          final expires = created.add(const Duration(days: 30));
          return ListTile(
            title: Text('${r.customerName} • ${r.model}'),
            subtitle: Text('Expires: ${expires.toLocal()}'),
            trailing: Text(r.status),
          );
        },
      ),
    );
  }
}

class AnalyticsPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final st = Provider.of<AppState>(context);
    final incomeSum = st.khata
        .where((e) => e.type == 'income')
        .fold<double>(0, (p, e) => p + e.amount);
    final expenseSum = st.khata
        .where((e) => e.type == 'expense')
        .fold<double>(0, (p, e) => p + e.amount);

    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(
              'Income: ₹${incomeSum.toStringAsFixed(2)}  •  Expense: ₹${expenseSum.toStringAsFixed(2)}',
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: [
                    PieChartSectionData(
                      value: incomeSum == 0 ? 1 : incomeSum,
                      title: 'Income',
                    ),
                    PieChartSectionData(
                      value: expenseSum == 0 ? 0.5 : expenseSum,
                      title: 'Expense',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: const Center(child: Text("Settings Page")),
    );
  }
}
