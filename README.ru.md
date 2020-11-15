# StateFlow (перловая имплементация)

## Что такое StateFlow

Это такая библиотека для манипуляции с данными в БД, в которой все структуры данных и dataflow задаются один раз декларативно, а потом просто накладываются обновления данных, которые эти библиотека распространяет по всей этой структуре согласно декларации.

При этом она учитывает статистику использования этих данных, и исходя из неё, может оптимизировать фактический dataflow выбирая степень агрессивности материализации вторичных структур данных.

## Пример

Есть таблица `comments` с пользовательскими полями:

- `id` - идентификатор комментария
- `topic_id` - идентификатор комментируемого топика
- `author_id` - идентификатор автора комменатрия

И автоматическими полями:

- `likes_cnt = comments_votes[ id = id, is_like = true ].count` - количество лайков.
- `dislikes_cnt = comments_votes[ id = id, is_like = false ].count` - количество дислайков.

Тогда если записей в таблицу `comments_votes` будет намного больше, чем чтений из `comments`, то автоматические поля `likes_cnt` и `dislikes_cnt` перестанут материализоваться, а будут при каждом чтении высчитываться отдельным запросом в таблицу `comments_votes`.  

А если чтений из таблицы `comments` будет намного больше, чем записей в `comments_votes` (что чаще всего и бывает), то автоматические поля `likes_cnt` и `dislikes_cnt` будут материализованными. Т.е. при каждом изменении `comments_votes` они будут обновляться.

## Магия

Ключевой особенностью StateFlow будет являться способность наиболее эффективно выстраивать политики обновления всех данных. Тут можно использовать много разного интересного анализа статистики dataflow.

## Помимо прочего

В планах реализовать контрольную панель dataflow, в которой удобно графически представить dataflow и отразить ключевые данные статистики.
