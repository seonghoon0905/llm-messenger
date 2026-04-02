import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/chat_room.dart';
import '../models/message.dart';


class DBHelper {
  static final DBHelper _instance = DBHelper._internal();
  static Database? _database;

  DBHelper._internal();

  factory DBHelper() => _instance;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    String path = join(await getDatabasesPath(), 'messenger.db');
    return await openDatabase(
      path,
      version: 1,
      onConfigure: (db) async {
        // 외래키 제약 조건 활성화 (매우 중요!)
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        // 1. 채팅방 테이블
        await db.execute('''
        CREATE TABLE chat_rooms(
          id TEXT PRIMARY KEY,
          title TEXT,
          relation TEXT,
          lastMessageTime TEXT
        )
      ''');

        // 2. 메시지 테이블 (외래키 설정)
        await db.execute('''
        CREATE TABLE messages(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          roomId TEXT,
          text TEXT,
          sender TEXT,
          timestamp TEXT,
          FOREIGN KEY (roomId) REFERENCES chat_rooms (id) ON DELETE CASCADE
        )
      ''');
      },
    );
  }

  // 메시지 저장 부분 (이제 message.sender가 존재하므로 에러 해결!)
  Future<void> insertMessage(String roomId, Message message) async {
    final db = await database;
    await db.insert('messages', {
      'roomId': roomId,
      'text': message.text,
      'sender': message.sender, // 이제 OK!
      'timestamp': message.timestamp.toIso8601String(),
    });
  }

// 특정 방의 메시지 불러오기 부분
  Future<List<Message>> getMessages(String roomId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'messages',
      where: 'roomId = ?',
      whereArgs: [roomId],
      orderBy: 'timestamp ASC',
    );

    return List.generate(maps.length, (i) {
      return Message(
        text: maps[i]['text'],
        sender: maps[i]['sender'], // 'isMe' 대신 'sender' 사용
        timestamp: DateTime.parse(maps[i]['timestamp']),
      );
    });
  }

  // 채팅방 저장
  Future<void> insertChatRoom(ChatRoom room) async {
    final db = await database;
    await db.insert(
      'chat_rooms',
      {
        'id': room.id,
        'title': room.title,
        'relation': room.relation,
        'lastMessageTime': room.lastMessageTime.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // 채팅방 목록 불러오기
  Future<List<ChatRoom>> getChatRooms() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('chat_rooms');

    return List.generate(maps.length, (i) {
      return ChatRoom(
        id: maps[i]['id'],
        title: maps[i]['title'],
        relation: maps[i]['relation'],
        lastMessageTime: DateTime.parse(maps[i]['lastMessageTime']),
        messages: [], // 메시지는 나중에 별도 테이블에서 불러와야 함
      );
    });
  }

  Future<void> updateChatRoom(ChatRoom room) async {
    final db = await database;
    await db.update(
      'chat_rooms',
      {
        'title': room.title,
        'relation': room.relation,
        'lastMessageTime': room.lastMessageTime.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [room.id],
    );
  }

  Future<void> deleteChatRoom(String roomId) async {
    final db = await database;
    await db.delete(
      'chat_rooms',
      where: 'id = ?',
      whereArgs: [roomId],
    );
  }
}