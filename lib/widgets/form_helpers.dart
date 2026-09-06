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

// ─── Vehicles section (Car + Bike rows, shared across dialogs) ──────────

class VehiclesSection extends StatelessWidget {
  final String isCarOwner;
  final String isBikeOwner;
  final TextEditingController carRegController;
  final TextEditingController bikeRegController;
  final bool hasAttemptedSubmit;
  final ValueChanged<String> onCarChanged;
  final ValueChanged<String> onBikeChanged;

  // Bike 2 support
  final bool hasBike2;
  final TextEditingController? bike2RegController;
  final ValueChanged<bool>? onBike2Changed;

  // Quota enforcement indicators
  final bool canAddCar;
  final int maxBikesAddable; // How many bikes can be added (0, 1, or 2)

  const VehiclesSection({
    super.key,
    required this.isCarOwner,
    required this.isBikeOwner,
    required this.carRegController,
    required this.bikeRegController,
    required this.hasAttemptedSubmit,
    required this.onCarChanged,
    required this.onBikeChanged,
    this.hasBike2 = false,
    this.bike2RegController,
    this.onBike2Changed,
    this.canAddCar = true,
    this.maxBikesAddable = 2,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(icon: Icons.directions_car, title: 'Vehicles (Max 1 Car & 2 Bikes per Flat)'),
          const SizedBox(height: 12),
          if (!canAddCar && isCarOwner != 'Yes')
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.red),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'This flat already has 1 Car assigned (Quota full).',
                        style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          _VehicleRow(
            label: 'Car?',
            regLabel: 'Car Reg. No. *',
            hasOwnership: isCarOwner == 'Yes',
            regController: carRegController,
            hasAttemptedSubmit: hasAttemptedSubmit,
            enabled: canAddCar || isCarOwner == 'Yes',
            onChanged: onCarChanged,
          ),
          const SizedBox(height: 12),
          if (maxBikesAddable <= 0 && isBikeOwner != 'Yes')
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.red),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'This flat already has 2 Bikes assigned (Quota full).',
                        style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          _VehicleRow(
            label: 'Bike?',
            regLabel: 'Bike 1 Reg. No. *',
            hasOwnership: isBikeOwner == 'Yes',
            regController: bikeRegController,
            hasAttemptedSubmit: hasAttemptedSubmit,
            enabled: maxBikesAddable > 0 || isBikeOwner == 'Yes',
            onChanged: (v) {
              onBikeChanged(v);
              if (v == 'No' && onBike2Changed != null) {
                onBike2Changed!(false);
              }
            },
          ),
          if (isBikeOwner == 'Yes' && bike2RegController != null && onBike2Changed != null) ...[
            const SizedBox(height: 8),
            if (!hasBike2 && maxBikesAddable >= 2)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('Add Another Bike (Max 2)'),
                  onPressed: () => onBike2Changed!(true),
                ),
              ),
            if (hasBike2) ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: bike2RegController,
                      decoration: kInput('Bike 2 Reg. No. *'),
                      textCapitalization: TextCapitalization.characters,
                      validator: (val) => (val == null || val.trim().isEmpty)
                          ? (hasAttemptedSubmit ? 'Required' : null)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.remove_circle, color: Colors.red),
                    tooltip: 'Remove Bike 2',
                    onPressed: () {
                      bike2RegController!.clear();
                      onBike2Changed!(false);
                    },
                  ),
                ],
              ),
            ],
          ],
        ],
      );
}

class _VehicleRow extends StatelessWidget {
  final String label;
  final String regLabel;
  final bool hasOwnership;
  final TextEditingController regController;
  final bool hasAttemptedSubmit;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _VehicleRow({
    required this.label,
    required this.regLabel,
    required this.hasOwnership,
    required this.regController,
    required this.hasAttemptedSubmit,
    this.enabled = true,
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
              onChanged: enabled ? (v) => onChanged(v!) : null,
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
                textCapitalization: TextCapitalization.characters,
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

