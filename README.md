# CineSphere

A premium cinematic streaming experience built with Flutter.

## Features

- 🎬 **Hero Carousel** – Swipeable featured movies with IMAX/4K badges  
- ▶️ **Continue Watching** – Progress bars on landscape cards  
- 🔍 **Search & Explore** – Genre browser + live search with filters  
- ⬇️ **Downloads** – Offline storage management  
- 📚 **Library** – Watchlist, Favorites, History  
- 🎨 **Design System** – CineSphere dark UI, Electric Violet primary, Sunset Coral CTA

## Getting Started

```bash
# 1) Provide your TMDB v3 API key (the local file is git-ignored)
cp lib/core/config/tmdb_key.example.dart lib/core/config/tmdb_key.local.dart
#    then edit lib/core/config/tmdb_key.local.dart with your key

flutter pub get
flutter run
```

## Architecture

```
lib/
├── main.dart
├── app.dart                    # Navigation shell
├── core/
│   ├── models/movie.dart       # Movie & TVShow models
│   ├── data/mock_data.dart     # Mock content
│   └── theme/
│       ├── app_colors.dart     # Design tokens
│       └── app_theme.dart      # ThemeData
├── features/
│   ├── home/                   # Home screen + media cards
│   ├── explore/                # Search & genre grid
│   ├── downloads/              # Offline manager
│   ├── detail/                 # Movie detail page
│   └── library/                # User library
└── shared/widgets/             # Reusable components
```
