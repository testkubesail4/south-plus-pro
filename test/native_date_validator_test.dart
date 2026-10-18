import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/services/native_date_validator.dart';

void main() {
  const years = ['1900', '1990', '2000', '2010', '2024'];
  const incomplete = '不完整的日期，请选择年、月、日或清空';
  const invalid = '日期不存在，请重新选择';

  test(
      'unset accepts null or empty, while every partial combination is rejected',
      () {
    for (final parts in <(String?, String?, String?)>[
      (null, null, null),
      ('', '', ''),
      (null, '', null),
    ]) {
      expect(
          validateNativeDate(
              year: parts.$1,
              month: parts.$2,
              day: parts.$3,
              yearOptions: years),
          isNull);
    }
    for (final parts in <(String?, String?, String?)>[
      ('1990', '', ''),
      ('', '6', ''),
      ('', '', '15'),
      ('1990', '6', null),
      ('1990', null, '15'),
      (null, '6', '15'),
    ]) {
      expect(
          validateNativeDate(
              year: parts.$1,
              month: parts.$2,
              day: parts.$3,
              yearOptions: years),
          incomplete,
          reason: '$parts');
    }
  });

  test('complete dates obey calendar rules and the native year options', () {
    for (final parts in <(String, String, String, bool)>[
      ('1990', '6', '15', true),
      ('2000', '2', '29', true),
      ('2024', '2', '29', true),
      ('1900', '2', '28', true),
      ('2010', '12', '31', true),
      ('1990', '2', '29', false),
      ('1990', '2', '30', false),
      ('1900', '2', '29', false),
      ('2010', '4', '31', false),
      ('2010', '0', '15', false),
      ('2010', '13', '15', false),
      ('2010', '6', '0', false),
      ('2010', '6', '32', false),
      ('1991', '6', '15', false),
      ('1959', '6', '15', false),
      ('2099', '6', '15', false),
      ('1990', 'six', '15', false),
      ('1990', '6.0', '15', false),
      ('1990', '+6', '15', false),
      ('1990', '6', '15 ', false),
      ('１９９０', '6', '15', false),
    ]) {
      final error = validateNativeDate(
          year: parts.$1, month: parts.$2, day: parts.$3, yearOptions: years);
      expect(error, parts.$4 ? isNull : invalid, reason: '$parts');
    }
  });

  test(
      'supplied month and day options restrict real dates but never make impossible dates valid',
      () {
    expect(
        validateNativeDate(
            year: '1990',
            month: '6',
            day: '15',
            yearOptions: years,
            monthOptions: ['6'],
            dayOptions: ['15']),
        isNull);
    expect(
        validateNativeDate(
            year: '1990',
            month: '6',
            day: '15',
            yearOptions: years,
            monthOptions: ['5'],
            dayOptions: ['15']),
        invalid);
    expect(
        validateNativeDate(
            year: '1990',
            month: '6',
            day: '15',
            yearOptions: years,
            monthOptions: ['6'],
            dayOptions: ['1', '16']),
        invalid);
    expect(
        validateNativeDate(
            year: '1990',
            month: '6',
            day: '15',
            yearOptions: years,
            monthOptions: [],
            dayOptions: ['15']),
        invalid);
    expect(
        validateNativeDate(
            year: '1990',
            month: '13',
            day: '1',
            yearOptions: years,
            monthOptions: ['13'],
            dayOptions: ['1']),
        invalid);
    expect(
        validateNativeDate(
            year: '1990',
            month: '2',
            day: '31',
            yearOptions: years,
            monthOptions: ['2'],
            dayOptions: ['31']),
        invalid);
    expect(
        validateNativeDate(
            year: '1990',
            month: '06',
            day: '15',
            yearOptions: years,
            monthOptions: ['6']),
        invalid);
    expect(
        validateNativeDate(
            year: '1990',
            month: '06',
            day: '15',
            yearOptions: years,
            monthOptions: ['06']),
        isNull);
  });

  test('native year options are authoritative, not a hardcoded interval', () {
    expect(
        validateNativeDate(
            year: '1940', month: '2', day: '29', yearOptions: ['1940']),
        isNull);
    expect(
        validateNativeDate(year: '0', month: '1', day: '1', yearOptions: ['0']),
        invalid);
    expect(
        validateNativeDate(
            year: '1000000000000',
            month: '1',
            day: '1',
            yearOptions: ['1000000000000']),
        invalid);
    expect(
        validateNativeDate(
            year: '',
            month: '',
            day: '',
            yearOptions: [],
            monthOptions: [],
            dayOptions: []),
        isNull);
  });
}
