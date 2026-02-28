class HelpStep {
  final String text;
  final String? instruction;

  const HelpStep({required this.text, this.instruction});
}

class HelpSpec<T> {
  final T id;
  final List<HelpStep> steps;

  const HelpSpec({required this.id, required this.steps});
}
