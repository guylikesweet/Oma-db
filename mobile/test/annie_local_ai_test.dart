import 'package:flutter_test/flutter_test.dart';
import 'package:oma_mobile/services/annie_local_ai.dart';

void main() {
  final annie = AnnieLocalAi.instance;

  test('fixed Oma policy questions do not require a model download', () {
    expect(AnnieLocalAi.canAnswerWithoutModel('When does demurrage start?'), isTrue);
    expect(AnnieLocalAi.canAnswerWithoutModel('What is our profit?'), isTrue);
    expect(AnnieLocalAi.canAnswerWithoutModel('Explain our shipment process'), isFalse);
    expect(AnnieLocalAi.canAnswerWithoutContext('When does demurrage start?'), isTrue);
    expect(AnnieLocalAi.canAnswerWithoutContext('What is our profit?'), isFalse);
  });

  test('uses the pinned official Qwen2.5 0.5B Q4_K_M model', () {
    expect(
      AnnieLocalAi.modelUrl,
      contains('/resolve/9217f5d/qwen2.5-0.5b-instruct-q4_k_m.gguf'),
    );
    expect(AnnieLocalAi.modelFileName, endsWith('.gguf'));
    expect(AnnieLocalAi.minimumModelBytes, greaterThan(400 * 1024 * 1024));
  });

  test('greetings are answered without downloading the model', () async {
    expect(AnnieLocalAi.canAnswerWithoutModel('hello'), isTrue);
    expect(AnnieLocalAi.canAnswerWithoutContext('good morning'), isTrue);
    final answer = await annie.answer(
      question: 'hello',
      businessContext: {'staff_role': 'staff'},
    );
    expect(answer, contains('Oma business assistant'));
  });

  test('local greeting is direct and does not ask a follow-up', () async {
    final answer = await annie.answer(
      question: 'hello',
      businessContext: {'staff_role': 'staff'},
    );
    expect(answer, "Hello! 😊 I’m Annie, Oma’s business assistant.");
    expect(answer, isNot(contains('?')));
  });

  test('does not disclose profit or margin to staff', () async {
    final answer = await annie.answer(
      question: 'What is our profit this week?',
      businessContext: {'staff_role': 'staff'},
    );
    expect(answer, contains('can’t share profit or margin'));
  });

  test('admin profit answer must come from the supplied database summary', () async {
    final answer = await annie.answer(
      question: 'What is our profit?',
      businessContext: {
        'staff_role': 'admin',
        'admin_only_financial_summary': {
          'profit_last_7_days_ngn': 12500,
        },
      },
    );
    expect(answer, contains('₦12500.00'));
    expect(answer, contains('last 7 days'));
  });

  test('offline admin cache without a financial summary cannot invent profit', () async {
    final answer = await annie.answer(
      question: 'What is our profit?',
      businessContext: {'staff_role': 'admin'},
      cachedSnapshot: true,
    );
    expect(answer, contains('can’t confirm the profit figure'));
  });

  test('cost-price questions never reach the model', () async {
    final answer = await annie.answer(
      question: 'What is the product cost price?',
      businessContext: {'staff_role': 'admin'},
    );
    expect(answer, contains('does not expose product cost information'));
  });

  test('demurrage always follows the day-six rule', () async {
    final answer = await annie.answer(
      question: 'When does demurrage start?',
      businessContext: {'staff_role': 'staff'},
    );
    expect(answer, contains('5 days'));
    expect(answer, contains('day 6'));
    expect(answer, contains('₦150 per piece per day'));
  });
}
