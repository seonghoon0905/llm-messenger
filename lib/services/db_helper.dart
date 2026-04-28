import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/chat_room.dart';
import '../models/message.dart';
import '../constants/app_style.dart';
import '../models/user_profile.dart';

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
    String dbName = "${AppStyle.myLoggedInId ?? 'default'}_local.db";
    String path = join(await getDatabasesPath(), dbName);
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE chat_rooms(id TEXT PRIMARY KEY, title TEXT, relation TEXT, lastMessageTime TEXT)',
        );
        await db.execute(
          'CREATE TABLE messages(id INTEGER PRIMARY KEY AUTOINCREMENT, roomId TEXT, text TEXT, sender TEXT, timestamp TEXT)',
        );
        await db.execute('''
          CREATE TABLE friends(
            userId TEXT PRIMARY KEY, 
            nickname TEXT, 
            statusMessage TEXT, 
            isSharingPersonality INTEGER,
            personalityStats TEXT,
            characterAction TEXT,
            characterDesc TEXT
          )
        ''');
      },
    );
  }

  Future<List<ChatRoom>> getChatRooms() async {
    final db = await database;

    // 1. 모든 채팅방 정보를 가져옵니다.
    final List<Map<String, dynamic>> maps = await db.query('chat_rooms');

    List<ChatRoom> rooms = [];

    for (var map in maps) {
      String roomId = map['id'];

      final List<Map<String, dynamic>> lastMsgMap = await db.query(
        'messages',
        where: 'roomId = ?',
        whereArgs: [roomId],
        orderBy: 'timestamp DESC',
        limit: 1,
      );

      String lastMessageText = "대화 내용이 없습니다.";
      if (lastMsgMap.isNotEmpty) {
        lastMessageText = lastMsgMap.first['text'];
      }

      rooms.add(
        ChatRoom(
          id: roomId,
          title: map['title'],
          relation: map['relation'],
          lastMessageTime: DateTime.parse(map['lastMessageTime']),
          lastMessage: lastMessageText,
        ),
      );
    }
    return rooms;
  }

  Future<void> insertChatRoom(ChatRoom room) async {
    final db = await database;
    await db.insert('chat_rooms', {
      'id': room.id,
      'title': room.title,
      'relation': room.relation,
      'lastMessageTime': room.lastMessageTime.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> insertMessage(String roomId, Message msg) async {
    final db = await database;
    await db.insert('messages', {
      'roomId': roomId,
      'text': msg.text,
      'sender': msg.sender,
      'timestamp': msg.timestamp.toIso8601String(),
    });
  }

  Future<List<Message>> getMessages(String roomId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'messages',
      where: 'roomId = ?',
      whereArgs: [roomId],
    );
    return maps
        .map(
          (m) => Message(
            text: m['text'],
            sender: m['sender'],
            timestamp: DateTime.parse(m['timestamp']),
          ),
        )
        .toList();
  }

  Future<void> deleteChatRoom(String roomId) async {
    final db = await database;

    // 트랜잭션을 사용하여 방과 메시지를 모두 안전하게 삭제
    await db.transaction((txn) async {
      // 해당 방의 모든 메시지 삭제
      await txn.delete('messages', where: 'roomId = ?', whereArgs: [roomId]);

      // 채팅방 삭제
      await txn.delete('chat_rooms', where: 'id = ?', whereArgs: [roomId]);
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

  // 2. 저장 및 불러오기 시에도 userId와 nickname을 구분해서 처리
  Future<void> insertFriend(UserProfile user) async {
    final db = await database;
    // user.toMap()을 사용하면 모델에 정의된 복잡한 변환 로직을 한 번에 쓸 수 있어 더 깔끔합니다.
    await db.insert(
      'friends',
      user.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteFriend(String userId) async {
    final db = await database;
    await db.delete('friends', where: 'userId = ?', whereArgs: [userId]);
  }

  Future<List<UserProfile>> getFriends() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('friends');
    return maps.map((m) => UserProfile.fromMap(m)).toList();
  }
}
