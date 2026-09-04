import 'package:flutter/material.dart';

// ─── Shared constants ────────────────────────────────────────────────────────

const kBlockOptions = ['A', 'B', 'C', 'D'];
const kYesNo = ['Yes', 'No'];

final kFlatNoRegex = RegExp(r'^\d{3}$');
final kPhoneRegex = RegExp(r'^\d{10}$');

// ─── Shared InputDecoration factory ──────────────────────────────────────────

InputDecoration kInput(String label, {IconData? icon}) => InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      isDense: true,
      prefixIcon: icon != null ? Icon(icon, size: 20) : null,
    );

// ─── Section header widget ────────────────────────────────────────────────────

class SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  const SectionHeader({super.key, required this.icon, required this.title});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, color: Colors.deepPurple, size: 20),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple)),
        ],
      );
}

// ─── Phone validator ──────────────────────────────────────────────────────────

String? phoneValidator(String? val, bool hasAttemptedSubmit) {
  if (val == null || val.trim().isEmpty) {
    return hasAttemptedSubmit ? 'Required' : null;
  }
  if (!kPhoneRegex.hasMatch(val.trim())) return 'Must be 10 digits';
  return null;
}

// ─── Vehicles section (Car + Bike rows, shared across three dialogs) ──────────

class VehiclesSection extends StatelessWidget {
  final String isCarOwner;
  final String isBikeOwner;
  final TextEditingController carRegController;
  final TextEditingController bikeRegController;
  final bool hasAttemptedSubmit;
  final ValueChanged<String> onCarChanged;
  final ValueChanged<String> onBikeChanged;

  const VehiclesSection({
    super.key,
    required this.isCarOwner,
    required this.isBikeOwner,
    required this.carRegController,
    required this.bikeRegController,
    required this.hasAttemptedSubmit,
    required this.onCarChanged,
    required this.onBikeChanged,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(icon: Icons.directions_car, title: 'Vehicles'),
          const SizedBox(height: 12),
          _VehicleRow(
            label: 'Car?',
            regLabel: 'Car Reg. No. *',
            hasOwnership: isCarOwner == 'Yes',
            regController: carRegController,
            hasAttemptedSubmit: hasAttemptedSubmit,
            onChanged: onCarChanged,
          ),
          const SizedBox(height: 12),
          _VehicleRow(
            label: 'Bike?',
            regLabel: 'Bike Reg. No. *',
            hasOwnership: isBikeOwner == 'Yes',
            regController: bikeRegController,
            hasAttemptedSubmit: hasAttemptedSubmit,
            onChanged: onBikeChanged,
          ),
        ],
      );
}

class _VehicleRow extends StatelessWidget {
  final String label;
  final String regLabel;
  final bool hasOwnership;
  final TextEditingController regController;
  final bool hasAttemptedSubmit;
  final ValueChanged<String> onChanged;

  const _VehicleRow({
    required this.label,
    required this.regLabel,
    required this.hasOwnership,
    required this.regController,
    required this.hasAttemptedSubmit,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 1,
            child: DropdownButtonFormField<String>(
              value: hasOwnership ? 'Yes' : 'No',
              items: kYesNo
                  .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                  .toList(),
              onChanged: (v) => onChanged(v!),
              decoration: kInput(label),
            ),
          ),
          if (hasOwnership) ...[
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: regController,
                decoration: kInput(regLabel),
                validator: (val) => hasOwnership &&
                        (val == null || val.trim().isEmpty)
                    ? (hasAttemptedSubmit ? 'Required' : null)
                    : null,
              ),
            ),
          ] else
            const Expanded(flex: 2, child: SizedBox()),
        ],
      );
}

