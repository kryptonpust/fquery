import 'package:flutter/scheduler.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:fquery_core/fquery_core.dart';

T useObservableSelector<T>(Observable observable, T Function() getValue) {
  final state = useState<T>(getValue());
  final mounted = useRef(true);
  // The listener is registered once, so it reads the getter of the latest
  // build (e.g. the current query key, not the first one).
  final latestGetValue = useRef(getValue)..value = getValue;

  useEffect(() {
    mounted.value = true;
    final id = identityHashCode(state);

    void listener() {
      if (!mounted.value) return;

      final schedulerBinding = SchedulerBinding.instance;
      if (schedulerBinding.schedulerPhase ==
          SchedulerPhase.persistentCallbacks) {
        // During build, defer to next frame
        schedulerBinding.addPostFrameCallback((_) {
          if (mounted.value) {
            state.value = latestGetValue.value();
          }
        });
      } else {
        state.value = latestGetValue.value();
      }
    }

    observable.subscribe(id, listener);

    return () {
      mounted.value = false;
      observable.unsubscribe(id);
    };
  }, [observable]);

  return state.value;
}
