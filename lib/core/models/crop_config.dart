/// Configuration for one photo/weight category within a crop workflow.
class PhotoCategoryConfig {
  final String key;
  final String label;
  final bool mandatory;

  const PhotoCategoryConfig({
    required this.key,
    required this.label,
    required this.mandatory,
  });
}

/// Configuration for one crop's data-collection workflow.
///
/// Adding a new crop or category only requires adding an entry here -
/// no screen code needs to change.
class CropConfig {
  final String cropType;
  final String displayName;
  final String idPrefix;
  final String firestoreCollection;
  final List<PhotoCategoryConfig> categories;

  const CropConfig({
    required this.cropType,
    required this.displayName,
    required this.idPrefix,
    required this.firestoreCollection,
    required this.categories,
  });
}

class CropCatalog {
  static const maize = CropConfig(
    cropType: 'maize',
    displayName: 'Maize',
    idPrefix: 'MZ',
    firestoreCollection: 'maize',
    categories: [
      PhotoCategoryConfig(key: 'whole', label: 'Whole', mandatory: true),
      PhotoCategoryConfig(
        key: 'broken',
        label: 'Broken Seed',
        mandatory: false,
      ),
      PhotoCategoryConfig(key: 'dust', label: 'Dust', mandatory: false),
      PhotoCategoryConfig(key: 'fungus', label: 'Fungus', mandatory: false),
      PhotoCategoryConfig(
        key: 'small',
        label: 'Small Seed',
        mandatory: false,
      ),
    ],
  );

  static const paddy = CropConfig(
    cropType: 'paddy',
    displayName: 'Paddy',
    idPrefix: 'PD',
    firestoreCollection: 'paddy',
    categories: [
      PhotoCategoryConfig(key: 'whole', label: 'Whole', mandatory: true),
      PhotoCategoryConfig(key: 'dust', label: 'Dust', mandatory: false),
      PhotoCategoryConfig(
        key: 'black',
        label: 'Black Grains',
        mandatory: false,
      ),
      PhotoCategoryConfig(
        key: 'immature',
        label: 'Immature Grains',
        mandatory: false,
      ),
      PhotoCategoryConfig(
        key: 'mixed',
        label: 'Mixed Grains',
        mandatory: false,
      ),
      PhotoCategoryConfig(
        key: 'empty',
        label: 'Empty Grains',
        mandatory: false,
      ),
      PhotoCategoryConfig(
        key: 'discolored',
        label: 'Discolored Grains',
        mandatory: false,
      ),
    ],
  );

  static const all = [maize, paddy];

  static CropConfig byType(String cropType) {
    return all.firstWhere((c) => c.cropType == cropType);
  }
}
