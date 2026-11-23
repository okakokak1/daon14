import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/customer.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('daon_crm.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE customers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            customer_type TEXT DEFAULT '개인',
            name TEXT NOT NULL,
            phone TEXT NOT NULL,
            address TEXT,
            device TEXT,
            symptom TEXT,
            amount TEXT,
            material_cost TEXT DEFAULT '0',
            payment_status TEXT,
            memo TEXT,
            visit_date TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute("ALTER TABLE customers ADD COLUMN material_cost TEXT DEFAULT '0'");
        }
        if (oldVersion < 3) {
          await db.execute("ALTER TABLE customers ADD COLUMN customer_type TEXT DEFAULT '개인'");
        }
      },
    );
  }

  Future<int> insertCustomer(Customer customer) async {
    final db = await instance.database;
    return await db.insert('customers', customer.toMap());
  }

  Future<List<Customer>> getCustomers([String query = '']) async {
    final db = await instance.database;
    if (query.isEmpty) {
      final result = await db.query('customers', orderBy: 'visit_date DESC, id DESC');
      return result.map((e) => Customer.fromMap(e)).toList();
    } else {
      final result = await db.query(
        'customers',
        where: 'name LIKE ? OR phone LIKE ? OR address LIKE ? OR symptom LIKE ? OR customer_type LIKE ?',
        whereArgs: ['%$query%', '%$query%', '%$query%', '%$query%', '%$query%'],
        orderBy: 'visit_date DESC, id DESC',
      );
      return result.map((e) => Customer.fromMap(e)).toList();
    }
  }

  Future<int> updateCustomer(Customer customer) async {
    final db = await instance.database;
    return await db.update(
      'customers',
      customer.toMap(),
      where: 'id = ?',
      whereArgs: [customer.id],
    );
  }

  Future<int> deleteCustomer(int id) async {
    final db = await instance.database;
    return await db.delete('customers', where: 'id = ?', whereArgs: [id]);
  }
}