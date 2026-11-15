import SwiftUI

/// A binding to the element of `array` with the same id as `element`.
///
/// `ForEach($array) { $element in … }` gives each row a binding that remembers the element's
/// *position*. If the element is deleted while a row (a Toggle or text field) is still
/// updating, that position is out of range and the app crashes. This looks the element up
/// by id each time instead: if it's gone, reading gives back the last known value and
/// writing does nothing.
func elementBinding<Element: Identifiable>(_ array: Binding<[Element]>, _ element: Element) -> Binding<Element> {
    let id = element.id
    return Binding(
        get: { array.wrappedValue.first { $0.id == id } ?? element },
        set: { newValue in
            if let index = array.wrappedValue.firstIndex(where: { $0.id == id }) {
                array.wrappedValue[index] = newValue
            }
        }
    )
}
