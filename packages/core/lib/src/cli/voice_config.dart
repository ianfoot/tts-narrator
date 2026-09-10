import '../narration/cost.dart';
import '../narration/model_profiles.dart';

/// The narrator gender a configured voice is tagged with.
enum VoiceGender {
  male,
  female,
  neutral;

  String get label => name;

  String get shorthand => switch (this) {
    VoiceGender.male => 'm',
    VoiceGender.female => 'f',
    VoiceGender.neutral => 'n',
  };
}

VoiceGender? parseVoiceGender(String? value) {
  if (value == null) return null;
  return switch (value.trim().toLowerCase()) {
    'male' => VoiceGender.male,
    'female' => VoiceGender.female,
    'neutral' => VoiceGender.neutral,
    _ => null,
  };
}

class Voice {
  const Voice({required this.id, this.gender});
  final String id;
  final VoiceGender? gender;
}

class VoiceOption {
  const VoiceOption({
    required this.model,
    required this.id,
    required this.label,
    required this.isAlias,
    this.gender,
  });
  final String model;
  final String id;
  final String label;
  final bool isAlias;
  final VoiceGender? gender;
}

class VoiceConfig {
  const VoiceConfig({
    this.defaultModel,
    this.providers = const {},
    this.models = const {},
    this.defaults = const {},
    this.pricing = const {},
    this.voices = const {},
  });

  final String? defaultModel;
  final Map<String, Map<String, String>> providers;
  final Map<String, TtsModelProfile> models;
  final Map<String, String> defaults;
  final Map<String, AudioPricing> pricing;
  final Map<String, Map<String, Voice>> voices;

  bool get isEmpty =>
      defaultModel == null &&
      providers.isEmpty &&
      models.isEmpty &&
      defaults.isEmpty &&
      pricing.isEmpty &&
      voices.isEmpty;
}

class VoiceConfigurationError implements Exception {
  VoiceConfigurationError(this.message);
  final String message;

  @override
  String toString() => message;
}
