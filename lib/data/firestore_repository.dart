import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../logic/finance.dart';
import '../models/models.dart';
import 'repository.dart';

/// Implementación con Firebase Auth + Cloud Firestore.
///
/// Estructura:
///   users/{uid}                         {name, householdId, households: {hid: nombre}, prefs}
///   invites/{codigo}                    {householdId, householdName, createdBy}
///   households/{hid}                    {name, memberIds, members: {uid: {name, privacy}},
///                                        currencies, wipe, plan}
///   households/{hid}/expenses/{id}      Expense + {public}
///   households/{hid}/recurring/{id}     RecurringExpense + {public}
///   households/{hid}/incomes/{id}
///   households/{hid}/settlements/{id}
///   households/{hid}/budgets/{id}
///
/// La privacidad se aplica en el servidor (ver firestore.rules): un gasto con
/// `public == false` solo lo puede leer quien lo pagó.
class FirestoreRepository implements Repository {
  FirestoreRepository({FirebaseAuth? auth, FirebaseFirestore? db})
      : _auth = auth ?? FirebaseAuth.instance,
        _db = db ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final _rand = Random.secure();

  String get _uid => _auth.currentUser!.uid;

  DocumentReference<Map<String, dynamic>> _household(String hid) =>
      _db.collection('households').doc(hid);
  CollectionReference<Map<String, dynamic>> _col(String hid, String name) =>
      _household(hid).collection(name);

  @override
  String newId() => _db.collection('_').doc().id;

  // --- Sesión ---
  @override
  Stream<AppUser?> watchUser() {
    return _auth.authStateChanges().asyncExpand((u) {
      if (u == null) return Stream.value(null);
      return _retry(() => _db.collection('users').doc(u.uid).snapshots()).map((s) {
        final d = s.data();
        final current = d?['householdId'] as String?;
        final households = <String, String>{
          for (final e in (d?['households'] as Map? ?? {}).entries)
            e.key as String: e.value as String? ?? '',
        };
        // Cuentas creadas antes de que existiera la lista de hogares.
        if (current != null) households.putIfAbsent(current, () => '');
        return AppUser(
          id: u.uid,
          name: d?['name'] as String? ?? u.displayName ?? u.email ?? 'Yo',
          householdId: current,
          households: households,
          prefs: UserPrefs.fromMap(d?['prefs'] as Map?),
        );
      });
    });
  }

  @override
  Future<void> signIn(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email.trim(), password: password);

  @override
  Future<void> register(String name, String email, String password) async {
    final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(), password: password);
    await cred.user!.updateDisplayName(name);
    await _db.collection('users').doc(cred.user!.uid).set({'name': name});
  }

  @override
  Future<void> signOut() => _auth.signOut();

  Future<String> _myName() async {
    final d = await _db.collection('users').doc(_uid).get();
    return d.data()?['name'] as String? ?? _auth.currentUser?.displayName ?? 'Yo';
  }

  // --- Hogar ---
  @override
  Future<String> createHousehold(String name) async {
    final hid = newId();
    final code = _code();
    final batch = _db.batch()
      ..set(_household(hid), {
        'name': name,
        'memberIds': [_uid],
        'members': {
          _uid: Member(id: _uid, name: await _myName()).toMap(),
        },
        'inviteCode': code,
        'currencies': [for (final c in defaultCurrencies) c.code],
      })
      ..set(_db.collection('invites').doc(code),
          {'householdId': hid, 'householdName': name, 'createdBy': _uid})
      ..set(
          _db.collection('users').doc(_uid),
          {
            'householdId': hid,
            'households': {hid: name},
          },
          SetOptions(merge: true));
    await batch.commit();
    return code;
  }

  @override
  Future<void> joinHousehold(String inviteCode) async {
    final code = inviteCode.trim().toUpperCase();
    final invite = await _db.collection('invites').doc(code).get();
    if (!invite.exists) throw StateError('Código de invitación inválido');
    final hid = invite.data()!['householdId'] as String;
    final batch = _db.batch()
      ..update(_household(hid), {
        'memberIds': FieldValue.arrayUnion([_uid]),
        'members.$_uid': Member(id: _uid, name: await _myName()).toMap(),
        'inviteCode': FieldValue.delete(),
      })
      ..delete(invite.reference)
      ..set(
          _db.collection('users').doc(_uid),
          {
            'householdId': hid,
            'households': {hid: invite.data()!['householdName'] as String? ?? ''},
          },
          SetOptions(merge: true));
    await batch.commit();
  }

  Household _householdFrom(DocumentSnapshot<Map<String, dynamic>> s) {
    final d = s.data()!;
    final ids = List<String>.from(d['memberIds'] as List);
    final members = (d['members'] as Map<String, dynamic>? ?? {});
    return Household(
      id: s.id,
      name: d['name'] as String? ?? 'Hogar',
      inviteCode: d['inviteCode'] as String?,
      plan: d['plan'] as String? ?? 'free',
      wipe: WipeRequest.fromMap(d['wipe'] as Map?),
      currencies: () {
        final list = [for (final c in d['currencies'] as List? ?? []) Currency.parse(c as String?)];
        return list.isEmpty ? defaultCurrencies : list;
      }(),
      members: [
        for (final id in ids)
          Member.fromMap(id, Map<String, dynamic>.from(members[id] as Map? ?? {})),
      ],
    );
  }

  @override
  Stream<Household> watchHousehold(String hid) =>
      _retry(() => _household(hid).snapshots()).where((s) => s.exists).map(_householdFrom);

  Future<Member?> _me(String hid) async =>
      _householdFrom(await _household(hid).get()).member(_uid);

  @override
  Future<void> setPrivacy(String hid, PrivacyMode mode) async {
    await _household(hid).update({'members.$_uid.privacy': mode.name});
    // Recalcula `public` en mis gastos personales con la nueva configuración.
    final me = (await _me(hid))!.copyWith(privacy: mode);
    final batch = _db.batch();
    final exp = await _col(hid, 'expenses')
        .where('paidBy', isEqualTo: _uid)
        .where('isShared', isEqualTo: false)
        .get();
    for (final d in exp.docs) {
      batch.update(d.reference, {'public': isPublic(Expense.fromMap(d.id, d.data()), me)});
    }
    final rec = await _col(hid, 'recurring')
        .where('paidBy', isEqualTo: _uid)
        .where('isShared', isEqualTo: false)
        .get();
    for (final d in rec.docs) {
      batch.update(d.reference,
          {'public': isPublic(RecurringExpense.fromMap(d.id, d.data()), me)});
    }
    await batch.commit();
  }

  @override
  Future<void> setCurrencies(String hid, List<Currency> currencies) =>
      _household(hid).update({
        'currencies': [for (final c in currencies) c.code],
      });

  @override
  Future<void> switchHousehold(String? id, {String? name}) =>
      _db.collection('users').doc(_uid).set({
        'householdId': id,
        if (id != null && name != null) 'households': {id: name},
      }, SetOptions(merge: true));

  @override
  Future<void> savePrefs(UserPrefs prefs) => _db
      .collection('users')
      .doc(_uid)
      .set({'prefs': prefs.toMap()}, SetOptions(merge: true));

  @override
  Future<void> setWipe(String hid, WipeRequest? wipe) =>
      _household(hid).update({'wipe': wipe?.toMap() ?? FieldValue.delete()});

  @override
  Future<void> wipeData(String hid, WipeScope scope) async {
    final refs = <DocumentReference>[];
    // Gastos: los compartidos y los propios (las reglas no dejan borrar los
    // personales de la pareja; esos los borra su app).
    for (final col in ['expenses', if (scope == WipeScope.all) 'recurring']) {
      final shared = await _col(hid, col).where('isShared', isEqualTo: true)
          .where('public', isEqualTo: true).get();
      final mine = await _col(hid, col).where('paidBy', isEqualTo: _uid).get();
      refs.addAll({
        for (final d in [...shared.docs, ...mine.docs]) d.reference.path: d.reference,
      }.values);
    }
    for (final col in ['incomes', 'settlements', if (scope == WipeScope.all) 'budgets']) {
      refs.addAll((await _col(hid, col).get()).docs.map((d) => d.reference));
    }
    for (var i = 0; i < refs.length; i += 400) {
      final batch = _db.batch();
      for (final r in refs.skip(i).take(400)) {
        batch.delete(r);
      }
      await batch.commit();
    }
  }

  // --- Movimientos ---

  /// Gastos públicos del hogar + todos los míos (incluidos los privados).
  /// Son dos consultas porque Firestore exige que cada consulta cumpla las
  /// reglas de seguridad por sí sola.
  Stream<List<T>> _visible<T>(
    String hid,
    String col,
    T Function(String id, Map<String, dynamic> m) parse,
  ) {
    final public = _retry(() => _col(hid, col).where('public', isEqualTo: true).snapshots());
    final mine = _retry(() => _col(hid, col).where('paidBy', isEqualTo: _uid).snapshots());
    return _combine(public, mine).map((pair) {
      final byId = <String, T>{};
      for (final snap in pair) {
        for (final d in snap.docs) {
          byId[d.id] = parse(d.id, d.data());
        }
      }
      return byId.values.toList();
    });
  }

  @override
  Stream<List<Expense>> watchExpenses(String hid) =>
      _visible(hid, 'expenses', Expense.fromMap)
          .map((l) => l..sort((a, b) => b.date.compareTo(a.date)));

  @override
  Stream<List<RecurringExpense>> watchRecurring(String hid) =>
      _visible(hid, 'recurring', RecurringExpense.fromMap);

  Stream<List<T>> _all<T>(String hid, String col,
          T Function(String id, Map<String, dynamic> m) parse) =>
      _retry(() => _col(hid, col).snapshots())
          .map((s) => [for (final d in s.docs) parse(d.id, d.data())]);

  @override
  Stream<List<Income>> watchIncomes(String hid) => _all(hid, 'incomes', Income.fromMap);
  @override
  Stream<List<Settlement>> watchSettlements(String hid) =>
      _all(hid, 'settlements', Settlement.fromMap);
  @override
  Stream<List<Budget>> watchBudgets(String hid) => _all(hid, 'budgets', Budget.fromMap);

  Future<Member?> _owner(String hid, String memberId) async =>
      _householdFrom(await _household(hid).get()).member(memberId);

  @override
  Future<void> saveExpense(String hid, Expense e) async {
    final owner = await _owner(hid, e.paidBy);
    await _col(hid, 'expenses').doc(e.id).set({...e.toMap(), 'public': isPublic(e, owner)});
  }

  @override
  Future<void> deleteExpense(String hid, String id) => _col(hid, 'expenses').doc(id).delete();

  @override
  Future<void> saveRecurring(String hid, RecurringExpense r) async {
    final owner = await _owner(hid, r.paidBy);
    await _col(hid, 'recurring').doc(r.id).set({...r.toMap(), 'public': isPublic(r, owner)});
  }

  @override
  Future<void> deleteRecurring(String hid, String id) =>
      _col(hid, 'recurring').doc(id).delete();
  @override
  Future<void> saveIncome(String hid, Income i) => _col(hid, 'incomes').doc(i.id).set(i.toMap());
  @override
  Future<void> deleteIncome(String hid, String id) => _col(hid, 'incomes').doc(id).delete();
  @override
  Future<void> saveSettlement(String hid, Settlement s) =>
      _col(hid, 'settlements').doc(s.id).set(s.toMap());
  @override
  Future<void> saveBudget(String hid, Budget b) => _col(hid, 'budgets').doc(b.id).set(b.toMap());
  @override
  Future<void> deleteBudget(String hid, String id) => _col(hid, 'budgets').doc(id).delete();

  String _code() => List.generate(
      8, (_) => 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'[_rand.nextInt(32)]).join();
}

/// Combina dos streams y emite el último valor de ambos cada vez que
/// cualquiera cambia (empieza cuando los dos emitieron al menos una vez).
Stream<List<T>> _combine<T>(Stream<T> a, Stream<T> b) {
  late StreamController<List<T>> ctrl;
  StreamSubscription<T>? sa, sb;
  T? la, lb;
  var hasA = false, hasB = false;
  void emit() {
    if (hasA && hasB) ctrl.add([la as T, lb as T]);
  }

  ctrl = StreamController<List<T>>(
    onListen: () {
      sa = a.listen((v) {
        la = v;
        hasA = true;
        emit();
      }, onError: ctrl.addError);
      sb = b.listen((v) {
        lb = v;
        hasB = true;
        emit();
      }, onError: ctrl.addError);
    },
    onCancel: () async {
      await sa?.cancel();
      await sb?.cancel();
    },
  );
  return ctrl.stream;
}

/// Vuelve a suscribirse si el stream falla. Pasa, por ejemplo, justo al crear
/// o unirse a un hogar: la app empieza a escuchar antes de que el servidor
/// termine de registrar el alta, Firestore rechaza la escucha por permisos y
/// sin reintento los datos no se actualizaban hasta reiniciar la app.
Stream<T> _retry<T>(Stream<T> Function() make) {
  late StreamController<T> ctrl;
  StreamSubscription<T>? sub;
  Timer? timer;
  var delay = 1;
  var closed = false;

  void listen() {
    sub = make().listen(
      (v) {
        delay = 1;
        ctrl.add(v);
      },
      onError: (Object e) {
        sub?.cancel();
        if (closed) return;
        timer = Timer(Duration(seconds: delay), listen);
        delay = min(delay * 2, 30);
      },
    );
  }

  ctrl = StreamController<T>(
    onListen: listen,
    onCancel: () async {
      closed = true;
      timer?.cancel();
      await sub?.cancel();
    },
  );
  return ctrl.stream;
}
