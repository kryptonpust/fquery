import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fquery/fquery.dart';
import 'package:fquery_core/fquery_core.dart';

const _cacheDuration = Duration(seconds: 2);

class _Reader extends HookWidget {
  const _Reader(this.queryKey, this.fetch, {super.key});

  final ValueListenable<List<Object>> queryKey;
  final Future<String> Function(List<Object> key) fetch;

  @override
  Widget build(BuildContext context) {
    final key = useValueListenable(queryKey);
    final query = useQuery<String, Exception>(
      key,
      () => fetch(key),
      context: context,
      cacheDuration: _cacheDuration,
    );
    return Text(query.data ?? 'none', textDirection: TextDirection.ltr);
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  late QueryCache cache;
  late Map<String, int> fetches;

  Future<String> fetch(List<Object> key) async {
    final id = key.join('/');
    fetches[id] = (fetches[id] ?? 0) + 1;
    return 'data:$id';
  }

  setUp(() {
    cache = QueryCache();
    fetches = {};
  });

  Widget app(ValueNotifier<bool> showSecond, ValueNotifier<List<Object>> key) {
    return CacheProvider(
      cache: cache,
      child: ValueListenableBuilder<bool>(
        valueListenable: showSecond,
        builder: (_, second, __) => Column(
          children: [
            _Reader(key, fetch),
            if (second) _Reader(ValueNotifier(key.value), fetch),
          ],
        ),
      ),
    );
  }

  testWidgets('keeps an observed query when another observer of it goes',
      (tester) async {
    final showSecond = ValueNotifier(true);
    final key = ValueNotifier<List<Object>>(['a']);
    await tester.pumpWidget(app(showSecond, key));
    await _settle(tester);
    expect(find.text('data:a'), findsNWidgets(2));

    showSecond.value = false;
    await _settle(tester);
    await tester.pump(_cacheDuration * 3);
    // Something else changes in the cache, which rebuilds the reader.
    cache.setQueryData<String, Exception>(['other'], (_) => 'x');
    await _settle(tester);

    expect(cache.queries[QueryKey(['a'])]?.data, 'data:a');
    expect(find.text('data:a'), findsOneWidget);
    expect(fetches['a'], 1);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(_cacheDuration * 2);
  });

  testWidgets('collects a query cacheDuration after its last observer goes',
      (tester) async {
    final showSecond = ValueNotifier(false);
    final key = ValueNotifier<List<Object>>(['a']);
    await tester.pumpWidget(app(showSecond, key));
    await _settle(tester);

    await tester.pumpWidget(CacheProvider(cache: cache, child: const SizedBox()));
    await tester.pump(_cacheDuration ~/ 2);
    expect(cache.queries.containsKey(QueryKey(['a'])), isTrue);

    await tester.pump(_cacheDuration);
    expect(cache.queries.containsKey(QueryKey(['a'])), isFalse);
  });

  testWidgets('refetches the current key when it is removed after a key change',
      (tester) async {
    final showSecond = ValueNotifier(false);
    final key = ValueNotifier<List<Object>>(['k', 1]);
    await tester.pumpWidget(app(showSecond, key));
    await _settle(tester);

    key.value = ['k', 2];
    await _settle(tester);
    expect(find.text('data:k/2'), findsOneWidget);

    cache.removeQueries(['k', 2], exact: true);
    cache.setQueryData<String, Exception>(['other'], (_) => 'x');
    await _settle(tester);

    expect(fetches['k/2'], 2);
    expect(find.text('data:k/2'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(_cacheDuration * 2);
  });
}
