import 'package:flutter_test/flutter_test.dart';

bool shouldDisplayEmailWarning({
  required String? personalEmail,
  required String? docEmail,
  required String? authEmail,
}) {
  final pEmail = (personalEmail ?? '').trim();
  final dEmail = (docEmail ?? '').trim().toLowerCase();
  final aEmail = (authEmail ?? '').trim().toLowerCase();

  final bool hasValidPersonalEmail = pEmail.isNotEmpty &&
      pEmail.contains('@') &&
      !pEmail.toLowerCase().endsWith('@ramkrishnapuram.com');

  final bool isDefaultSocietyEmail = aEmail.endsWith('@ramkrishnapuram.com') ||
      dEmail.endsWith('@ramkrishnapuram.com') ||
      dEmail.isEmpty;

  return !hasValidPersonalEmail && isDefaultSocietyEmail;
}

String? validatePersonalEmail(String? value) {
  final val = value?.trim() ?? '';
  if (val.isEmpty) return 'Please enter your email address';
  if (!RegExp(r'^[\w\.-]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(val)) {
    return 'Please enter a valid email address';
  }
  if (val.toLowerCase().endsWith('@ramkrishnapuram.com')) {
    return 'Please enter your personal email address, not the society placeholder';
  }
  return null;
}

void main() {
  group('Resident Default Email Warning Logic Tests', () {
    test('Shows warning when user is on default flat email without personal email', () {
      expect(
        shouldDisplayEmailWarning(
          personalEmail: null,
          docEmail: 'd-206@ramkrishnapuram.com',
          authEmail: 'd-206@ramkrishnapuram.com',
        ),
        isTrue,
      );

      expect(
        shouldDisplayEmailWarning(
          personalEmail: '',
          docEmail: 'a-212@ramkrishnapuram.com',
          authEmail: 'a-212@ramkrishnapuram.com',
        ),
        isTrue,
      );
    });

    test('Does NOT show warning once personal email is entered', () {
      expect(
        shouldDisplayEmailWarning(
          personalEmail: 'jit.mukherjee93@yahoo.com',
          docEmail: 'jit.mukherjee93@yahoo.com',
          authEmail: 'd-206@ramkrishnapuram.com',
        ),
        isFalse,
      );

      expect(
        shouldDisplayEmailWarning(
          personalEmail: 'resident@gmail.com',
          docEmail: 'a-212@ramkrishnapuram.com',
          authEmail: 'a-212@ramkrishnapuram.com',
        ),
        isFalse,
      );
    });

    test('Validates personal email correctly', () {
      expect(validatePersonalEmail(null), 'Please enter your email address');
      expect(validatePersonalEmail(''), 'Please enter your email address');
      expect(validatePersonalEmail('invalid_email'), 'Please enter a valid email address');
      expect(
        validatePersonalEmail('b-102@ramkrishnapuram.com'),
        'Please enter your personal email address, not the society placeholder',
      );
      expect(validatePersonalEmail('jit.mukherjee93@yahoo.com'), isNull);
      expect(validatePersonalEmail('resident.name@gmail.com'), isNull);
    });

    test('Blocks flat ID and default email login once personal email is registered', () {
      bool isLoginBlocked({required String input, required String? registeredPersonalEmail}) {
        final cleanInput = input.trim().toLowerCase();
        final bool isFlatOrSocietyEmailInput =
            !cleanInput.contains('@') || cleanInput.endsWith('@ramkrishnapuram.com');
        if (!isFlatOrSocietyEmailInput) return false; // Email login allowed
        final pEmail = (registeredPersonalEmail ?? '').trim();
        final bool hasUpdatedEmail = pEmail.isNotEmpty &&
            pEmail.contains('@') &&
            !pEmail.toLowerCase().endsWith('@ramkrishnapuram.com');
        return hasUpdatedEmail;
      }

      // User has updated email: flat and society email logins MUST be blocked
      expect(
        isLoginBlocked(input: 'd-206', registeredPersonalEmail: 'jit.mukherjee93@yahoo.com'),
        isTrue,
      );
      expect(
        isLoginBlocked(input: 'D-206', registeredPersonalEmail: 'jit.mukherjee93@yahoo.com'),
        isTrue,
      );
      expect(
        isLoginBlocked(input: 'd-206@ramkrishnapuram.com', registeredPersonalEmail: 'jit.mukherjee93@yahoo.com'),
        isTrue,
      );
      // But email login is NOT blocked
      expect(
        isLoginBlocked(input: 'jit.mukherjee93@yahoo.com', registeredPersonalEmail: 'jit.mukherjee93@yahoo.com'),
        isFalse,
      );

      // User has NOT updated email: flat login is permitted
      expect(
        isLoginBlocked(input: 'd-206', registeredPersonalEmail: null),
        isFalse,
      );
      expect(
        isLoginBlocked(input: 'd-206@ramkrishnapuram.com', registeredPersonalEmail: ''),
        isFalse,
      );
    });
  });
}

