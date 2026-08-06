/// What kind of value accompanies a category's photo.
enum CategoryFieldType {
  /// Numeric weight in grams (e.g. Whole, Broken Seed, Black Grains).
  weight,

  /// Free text (e.g. Consignment, Buyer/PO).
  text,
}

/// Configuration for one photo/value category within a crop workflow.
class PhotoCategoryConfig {
  final String key;
  final String label;
  final String labelBn;
  final bool mandatory;
  final CategoryFieldType fieldType;

  /// If true, the photo and value must both be present or both be absent
  /// (e.g. weight categories). If false, the photo and value are each
  /// independently optional (e.g. Consignment, Buyer/PO).
  final bool pairedValidation;

  const PhotoCategoryConfig({
    required this.key,
    required this.label,
    required this.labelBn,
    required this.mandatory,
    this.fieldType = CategoryFieldType.weight,
    this.pairedValidation = true,
  });

  /// Display label combining English and Bangla, e.g. "Whole(মোট স্যাম্পল)".
  String get bilingualLabel => '$label($labelBn)';
}

/// Configuration for one crop's data-collection workflow.
///
/// Adding a new crop or category only requires adding an entry here -
/// no screen code needs to change.
class CropConfig {
  final String cropType;
  final String displayName;
  final String displayNameBn;
  final String idPrefix;
  final String firestoreCollection;
  final List<PhotoCategoryConfig> categories;

  /// Summary popup title, e.g. "ধান পরিক্ষার বিবরণ:".
  final String summaryTitleBn;

  /// Summary popup label for the Whole-category weight line, e.g.
  /// "ধানের ওজন" (crop-specific, different from the Whole category's own
  /// bilingual label used on the entry form).
  final String wholeWeightLabelBn;

  const CropConfig({
    required this.cropType,
    required this.displayName,
    required this.displayNameBn,
    required this.idPrefix,
    required this.firestoreCollection,
    required this.categories,
    required this.summaryTitleBn,
    required this.wholeWeightLabelBn,
  });

  String get bilingualDisplayName => '$displayName($displayNameBn)';

  /// Weight categories eligible for the summary popup's percentage-of-Whole
  /// calculation: excludes Whole itself and any text-type category.
  List<PhotoCategoryConfig> get summaryPercentageCategories => categories
      .where((c) => c.key != 'whole' && c.fieldType == CategoryFieldType.weight)
      .toList();
}

/// Fixed Bangla label for the Moisture line in the summary popup - the
/// same term applies to both crops.
const moistureLabelBn = 'ময়েশ্চার';

// Consignment and Buyer/PO are identical across crops - defined once and
// reused so both crop configs stay in sync automatically.
const _consignment = PhotoCategoryConfig(
  key: 'consignment',
  label: 'Consignment',
  labelBn: 'চালান',
  mandatory: false,
  fieldType: CategoryFieldType.text,
  pairedValidation: false,
);

const _buyerPo = PhotoCategoryConfig(
  key: 'buyerPo',
  label: 'Buyer/PO',
  labelBn: 'ক্রেতা',
  mandatory: false,
  fieldType: CategoryFieldType.text,
  pairedValidation: false,
);

class CropCatalog {
  static const maize = CropConfig(
    cropType: 'maize',
    displayName: 'Maize',
    displayNameBn: 'ভুট্টা',
    idPrefix: 'MZ',
    firestoreCollection: 'maize',
    summaryTitleBn: 'ভুট্টা পরিক্ষার বিবরণ :',
    wholeWeightLabelBn: 'ভুট্টার ওজন',
    categories: [
      PhotoCategoryConfig(
        key: 'whole',
        label: 'Whole',
        labelBn: 'মোট স্যাম্পল',
        mandatory: true,
      ),
      PhotoCategoryConfig(
        key: 'broken',
        label: 'Broken Seed',
        labelBn: 'ভাঙ্গা দানা',
        mandatory: false,
      ),
      PhotoCategoryConfig(
        key: 'dust',
        label: 'Dust',
        labelBn: 'ডাস্ট',
        mandatory: false,
      ),
      PhotoCategoryConfig(
        key: 'fungus',
        label: 'Fungus',
        labelBn: 'ফাঙ্গাস',
        mandatory: false,
      ),
      PhotoCategoryConfig(
        key: 'small',
        label: 'Small Seed',
        labelBn: 'ছোট দানা',
        mandatory: false,
      ),
      PhotoCategoryConfig(
        key: 'black',
        label: 'Black Grains',
        labelBn: 'কালোদানা',
        mandatory: false,
      ),
      _consignment,
      _buyerPo,
    ],
  );

  static const paddy = CropConfig(
    cropType: 'paddy',
    displayName: 'Paddy',
    displayNameBn: 'ধান',
    idPrefix: 'PD',
    firestoreCollection: 'paddy',
    summaryTitleBn: 'ধান পরিক্ষার বিবরণ:',
    wholeWeightLabelBn: 'ধানের ওজন',
    categories: [
      PhotoCategoryConfig(
        key: 'whole',
        label: 'Whole',
        labelBn: 'মোট স্যাম্পল',
        mandatory: true,
      ),
      PhotoCategoryConfig(
        key: 'dust',
        label: 'Dust',
        labelBn: 'ডাস্ট',
        mandatory: false,
      ),
      PhotoCategoryConfig(
        key: 'black',
        label: 'Black Grains',
        labelBn: 'কালোদানা',
        mandatory: false,
      ),
      PhotoCategoryConfig(
        key: 'immature',
        label: 'Immature Grains',
        labelBn: 'অপরিপক্ক দানা',
        mandatory: false,
      ),
      PhotoCategoryConfig(
        key: 'mixed',
        label: 'Mixed Grains',
        labelBn: 'মিক্স দানা',
        mandatory: false,
      ),
      PhotoCategoryConfig(
        key: 'empty',
        label: 'Empty Grains',
        labelBn: 'চিতা/পাতান',
        mandatory: false,
      ),
      PhotoCategoryConfig(
        key: 'discolored',
        label: 'Discolored Grains',
        labelBn: 'তামরি',
        mandatory: false,
      ),
      _consignment,
      _buyerPo,
    ],
  );

  static const all = [maize, paddy];

  static CropConfig byType(String cropType) {
    return all.firstWhere((c) => c.cropType == cropType);
  }
}
