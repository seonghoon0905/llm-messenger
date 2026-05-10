import 'dart:convert';
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
    final dbName = "${AppStyle.myLoggedInId ?? 'default'}_local.db";
    final path = join(await getDatabasesPath(), dbName);
    return await openDatabase(
      path,
      version: 4,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE chat_rooms(
            id TEXT PRIMARY KEY,
            title TEXT,
            relation TEXT,
            lastMessageTime TEXT,
            unreadCount INTEGER DEFAULT 0,
            memberIds TEXT DEFAULT '[]'
          )
        ''');
        await db.execute('''
          CREATE TABLE messages(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            roomId TEXT,
            text TEXT,
            sender TEXT,
            timestamp TEXT,
            isRead INTEGER DEFAULT 0,
            replyToId INTEGER,
            replyToText TEXT,
            replyToSender TEXT,
            reactions TEXT DEFAULT '{}',
            isDeleted INTEGER DEFAULT 0,
            editedText TEXT
          )
        ''');
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
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
              'ALTER TABLE chat_rooms ADD COLUMN unreadCount INTEGER DEFAULT 0');
        }
        if (oldVersion < 3) {
          await db.execute(
              'ALTER TABLE messages ADD COLUMN isRead INTEGER DEFAULT 0');
          await db.execute(
              'ALTER TABLE messages ADD COLUMN replyToId INTEGER');
          await db.execute(
              'ALTER TABLE messages ADD COLUMN replyToText TEXT');
          await db.execute(
              'ALTER TABLE messages ADD COLUMN replyToSender TEXT');
          await db.execute(
              "ALTER TABLE messages ADD COLUMN reactions TEXT DEFAULT '{}'");
          await db.execute(
              'ALTER TABLE messages ADD COLUMN isDeleted INTEGER DEFAULT 0');
          await db.execute(
              'ALTER TABLE messages ADD COLUMN editedText TEXT');
        }
        if (oldVersion < 4) {
          await db.execute(
              "ALTER TABLE chat_rooms ADD COLUMN memberIds TEXT DEFAULT '[]'");
        }
      },
    );
  }

  // ─── Chat Rooms ───────────────────────────────────────────────────────────

  List<String> _decodeMemberIds(dynamic raw) {
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw as String) as List;
      return list.map((e) => e.toString()).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<ChatRoom>> getChatRooms() async {
    final db = await database;
    final maps = await db.query('chat_rooms', orderBy: 'lastMessageTime DESC');
    final rooms = <ChatRoom>[];
    for (var map in maps) {
      final roomId = map['id'] as String;
      final lastMsgMap = await db.query(
        'messages',
        where: 'roomId = ? AND isDeleted = 0',
        whereArgs: [roomId],
        orderBy: 'timestamp DESC',
        limit: 1,
      );
      final lastMessageText = lastMsgMap.isNotEmpty
          ? (lastMsgMap.first['editedText'] as String? ??
              lastMsgMap.first['text'] as String)
          : '대화 내용이 없습니다.';
      // lastMessageTime을 실제 마지막 메시지 시간 기준으로 보정
      DateTime lastTime = DateTime.parse(map['lastMessageTime'] as String);
      if (lastMsgMap.isNotEmpty) {
        final msgTime = DateTime.tryParse(lastMsgMap.first['timestamp'] as String? ?? '');
        if (msgTime != null && msgTime.isAfter(lastTime)) {
          lastTime = msgTime;
        }
      }
      rooms.add(ChatRoom(
        id: roomId,
        title: map['title'] as String,
        relation: map['relation'] as String,
        lastMessageTime: lastTime,
        lastMessage: lastMessageText,
        unreadCount: map['unreadCount'] as int? ?? 0,
        memberIds: _decodeMemberIds(map['memberIds']),
      ));
    }
    return rooms;
  }

  Future<void> insertChatRoom(ChatRoom room) async {
    final db = await database;
    await db.insert(
      'chat_rooms',
      {
        'id': room.id,
        'title': room.title,
        'relation': room.relation,
        'lastMessageTime': room.lastMessageTime.toIso8601String(),
        'unreadCount': room.unreadCount,
        'memberIds': jsonEncode(room.memberIds),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 서버 동기화 시 기존 방 데이터를 덮어쓰지 않음
  Future<void> insertChatRoomIfAbsent(ChatRoom room) async {
    final existing = await getChatRoomById(room.id);
    if (existing == null) {
      await insertChatRoom(room);
    }
  }

  Future<void> updateRoomMembers(String roomId, List<String> memberIds) async {
    final db = await database;
    await db.update(
      'chat_rooms',
      {'memberIds': jsonEncode(memberIds)},
      where: 'id = ?',
      whereArgs: [roomId],
    );
  }

  /// memberIds를 건드리지 않고 lastMessageTime과 unreadCount만 업데이트
  Future<void> updateRoomLastMessage(String roomId, DateTime time) async {
    final db = await database;
    await db.update(
      'chat_rooms',
      {'lastMessageTime': time.toIso8601String(), 'unreadCount': 0},
      where: 'id = ?',
      whereArgs: [roomId],
    );
  }

  Future<void> deleteChatRoom(String roomId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('messages', where: 'roomId = ?', whereArgs: [roomId]);
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
        'unreadCount': room.unreadCount,
        'memberIds': jsonEncode(room.memberIds),
      },
      where: 'id = ?',
      whereArgs: [room.id],
    );
  }

  Future<ChatRoom?> getChatRoomById(String roomId) async {
    final db = await database;
    final maps = await db.query('chat_rooms',
        where: 'id = ?', whereArgs: [roomId], limit: 1);
    if (maps.isEmpty) return null;
    final map = maps.first;
    return ChatRoom(
      id: map['id'] as String,
      title: map['title'] as String,
      relation: map['relation'] as String,
      lastMessageTime: DateTime.parse(map['lastMessageTime'] as String),
      unreadCount: map['unreadCount'] as int? ?? 0,
      memberIds: _decodeMemberIds(map['memberIds']),
    );
  }

  Future<void> upsertIncomingChatRoom({
    required String roomId,
    required String title,
    required String relation,
    required DateTime timestamp,
    bool incrementUnread = false,
  }) async {
    final existing = await getChatRoomById(roomId);
    final unreadCount = incrementUnread
        ? ((existing?.unreadCount ?? 0) + 1)
        : (existing?.unreadCount ?? 0);
    await insertChatRoom(ChatRoom(
      id: roomId,
      title: title,
      relation: relation,
      lastMessageTime: timestamp,
      unreadCount: unreadCount,
      memberIds: existing?.memberIds ?? [],
    ));
  }

  Future<void> resetUnreadCount(String roomId) async {
    final db = await database;
    await db.update('chat_rooms', {'unreadCount': 0},
        where: 'id = ?', whereArgs: [roomId]);
  }

  // ─── Messages ─────────────────────────────────────────────────────────────

  Future<int> insertMessage(String roomId, Message msg) async {
    final db = await database;
    return await db.insert('messages', msg.toDbMap(roomId));
  }

  Future<List<Message>> getMessages(String roomId) async {
    final db = await database;
    final maps = await db.query('messages',
        where: 'roomId = ?', whereArgs: [roomId]);
    return maps.map(Message.fromMap).toList();
  }

  Future<List<Message>> searchMessages(String roomId, String query) async {
    final db = await database;
    final maps = await db.query(
      'messages',
      where: 'roomId = ? AND (text LIKE ? OR editedText LIKE ?) AND isDeleted = 0',
      whereArgs: [roomId, '%$query%', '%$query%'],
      orderBy: 'timestamp ASC',
    );
    return maps.map(Message.fromMap).toList();
  }

  Future<void> deleteMessage(int id) async {
    final db = await database;
    await db.update('messages', {'isDeleted': 1},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> editMessage(int id, String newText) async {
    final db = await database;
    await db.update('messages', {'editedText': newText},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateReactions(
      int id, Map<String, List<String>> reactions) async {
    final db = await database;
    await db.update('messages', {'reactions': jsonEncode(reactions)},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markRoomMessagesAsRead(String roomId) async {
    final db = await database;
    await db.update(
      'messages',
      {'isRead': 1},
      where: "roomId = ? AND sender != 'me'",
      whereArgs: [roomId],
    );
  }

  Future<void> markMySentMessagesAsRead(String roomId) async {
    final db = await database;
    await db.update(
      'messages',
      {'isRead': 1},
      where: "roomId = ? AND sender = 'me'",
      whereArgs: [roomId],
    );
  }

  // ─── Friends ──────────────────────────────────────────────────────────────

  Future<void> insertFriend(UserProfile user) async {
    final db = await database;
    await db.insert('friends', user.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteFriend(String userId) async {
    final db = await database;
    await db.delete('friends', where: 'userId = ?', whereArgs: [userId]);
  }

  Future<List<UserProfile>> getFriends() async {
    final db = await database;
    final maps = await db.query('friends');
    return maps.map(UserProfile.fromMap).toList();
  }

  // ─── Account ──────────────────────────────────────────────────────────────

  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('messages');
    await db.delete('chat_rooms');
    await db.delete('friends');
  }
}
