import 'package:cloud_firestore/cloud_firestore.dart';

const int maxFavoriteMovies = 5;

const List<String> letterSizes = ['XS', 'S', 'M', 'L', 'XL', 'XXL'];

String zodiacSignFor(DateTime birthday) {
  final day = birthday.day;
  final month = birthday.month;
  const cusps = [
    [1, 20, 'Capricorn'], [2, 19, 'Aquarius'], [3, 20, 'Pisces'],
    [4, 20, 'Aries'], [5, 21, 'Taurus'], [6, 21, 'Gemini'],
    [7, 22, 'Cancer'], [8, 23, 'Leo'], [9, 23, 'Virgo'],
    [10, 23, 'Libra'], [11, 22, 'Scorpio'], [12, 21, 'Sagittarius'],
  ];
  const signsAfterCusp = [
    'Aquarius', 'Pisces', 'Aries', 'Taurus', 'Gemini', 'Cancer',
    'Leo', 'Virgo', 'Libra', 'Scorpio', 'Sagittarius', 'Capricorn',
  ];
  final cusp = cusps[month - 1];
  return day <= (cusp[1] as int) ? cusp[2] as String : signsAfterCusp[month - 1];
}

class PartnerProfile {
  final DateTime? birthday;
  // Proportion label (e.g. "Top", "Bottom", "Dress") -> size value.
  // Value can be a letter size (XS-XXL) or a numeric size, free text either way.
  final Map<String, String> clothingSizes;
  final String? shoeSize;
  final String? ringSize;
  final List<String> allergies;
  final List<String> foodDislikes;
  final List<String> favoriteFoods;
  final String? favoriteColor;
  final List<String> favoriteMovies;

  const PartnerProfile({
    this.birthday,
    this.clothingSizes = const {},
    this.shoeSize,
    this.ringSize,
    this.allergies = const [],
    this.foodDislikes = const [],
    this.favoriteFoods = const [],
    this.favoriteColor,
    this.favoriteMovies = const [],
  });

  factory PartnerProfile.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const PartnerProfile();
    return PartnerProfile(
      birthday: map['birthday'] != null
          ? (map['birthday'] as Timestamp).toDate()
          : null,
      clothingSizes: (map['clothingSizes'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as String)) ??
          const {},
      shoeSize: map['shoeSize'] as String?,
      ringSize: map['ringSize'] as String?,
      allergies: (map['allergies'] as List<dynamic>?)?.cast<String>() ??
          const [],
      foodDislikes:
          (map['foodDislikes'] as List<dynamic>?)?.cast<String>() ?? const [],
      favoriteFoods:
          (map['favoriteFoods'] as List<dynamic>?)?.cast<String>() ?? const [],
      favoriteColor: map['favoriteColor'] as String?,
      favoriteMovies:
          (map['favoriteMovies'] as List<dynamic>?)?.cast<String>() ??
              const [],
    );
  }

  Map<String, dynamic> toMap() => {
        'birthday': birthday != null ? Timestamp.fromDate(birthday!) : null,
        'clothingSizes': clothingSizes,
        'shoeSize': shoeSize,
        'ringSize': ringSize,
        'allergies': allergies,
        'foodDislikes': foodDislikes,
        'favoriteFoods': favoriteFoods,
        'favoriteColor': favoriteColor,
        'favoriteMovies': favoriteMovies,
      };

  PartnerProfile copyWith({
    DateTime? birthday,
    Map<String, String>? clothingSizes,
    String? shoeSize,
    String? ringSize,
    List<String>? allergies,
    List<String>? foodDislikes,
    List<String>? favoriteFoods,
    String? favoriteColor,
    List<String>? favoriteMovies,
  }) =>
      PartnerProfile(
        birthday: birthday ?? this.birthday,
        clothingSizes: clothingSizes ?? this.clothingSizes,
        shoeSize: shoeSize ?? this.shoeSize,
        ringSize: ringSize ?? this.ringSize,
        allergies: allergies ?? this.allergies,
        foodDislikes: foodDislikes ?? this.foodDislikes,
        favoriteFoods: favoriteFoods ?? this.favoriteFoods,
        favoriteColor: favoriteColor ?? this.favoriteColor,
        favoriteMovies: favoriteMovies ?? this.favoriteMovies,
      );
}
