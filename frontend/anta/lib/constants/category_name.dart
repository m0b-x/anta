/// The longest name a category may be given, in characters — the editor's
/// field limit, named here beside its counter threshold the way the event
/// title's pair is, so the two never drift apart in the sheet. The category
/// picker hands a typed query to the editor as the field's initial text
/// without reading this: the editor clamps that text to it, since the
/// field's own limit governs only what is typed next.
const int kCategoryNameMaxLength = 40;

/// The length from which the name field shows its counter: quiet for an
/// ordinary name, counting once the limit is in sight.
const int kCategoryNameCounterFrom = 30;

/// The longest own word a category's kept mark may be given ("Walked"): it
/// stands where a stock verb does, on a detail sheet's chip and a button's
/// tooltip, which a phrase would outgrow.
const int kCategoryMarkWordMaxLength = 20;
