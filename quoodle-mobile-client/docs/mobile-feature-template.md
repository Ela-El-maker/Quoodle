# Feature Module Template

Use this template for every new or migrated feature.

## Folder Layout

`lib/features/<feature>/`

- `presentation/`
- `providers/` (controller + state + providers)
- `screens/`
- `widgets/`
- `domain/`
- `entities/`
- `repositories/` (contracts)
- `usecases/`
- `data/`
- `datasources/`
- `repositories/` (implementations)
- `dtos/` and `mappers/` when needed

## Required Items

- Explicit feature state class.
- Controller (Riverpod Notifier/AsyncNotifier).
- Repository interface in domain.
- Repository implementation in data.
- At least one use case per meaningful action.
- Failure-safe handling (typed `Result<T>`).

## Review Checklist

- Presentation depends only on providers/use cases, not data sources.
- Domain has no Flutter imports.
- Loading/error/success behavior is explicit.
- Routes and navigation are centralized (no duplicated route arrays).
- Use `AppNavigator`/GoRouter navigation primitives (no `Navigator.pushNamed*`).
- No imports from legacy `lib/services/*` or `core/app_export.dart`.
- Unit/widget tests exist for key state transitions.
