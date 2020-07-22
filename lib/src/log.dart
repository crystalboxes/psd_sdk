const PSD_ENABLE_LOGGING = true;

void psdWarning(List<String> args) {
  if (PSD_ENABLE_LOGGING) {
    final channel = args[0];
    print(
        '***WARNING*** [$channel] ${args.sublist(1).reduce((value, element) => "$value $element")}');
  }
}

void psdError(List<String> args) {
  if (PSD_ENABLE_LOGGING) {
    final channel = args[0];
    print(
        '***ERROR*** [$channel] ${args.sublist(1).reduce((value, element) => "$value $element")}');
  }
}
