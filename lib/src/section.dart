/// A struct storing data for any section in a .PSD file.
class Section {
  /// The offset from the start of the file where this section is stored.
  int offset;

  /// The length of the section.
  int length;
}
