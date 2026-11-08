import Foundation

/// Launch arguments used by CI to open specific screens for screenshots
/// (debug builds only), e.g. `-initialTab defects -demoScreen specs`.
enum DemoConfig {
    static var initialTab: MainTabView.Tab? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "initialTab").flatMap(MainTabView.Tab.init(rawValue:))
        #else
        return nil
        #endif
    }

    /// vehicle, specs, checklist, defect, members, storage, checklists
    static var screen: String? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "demoScreen")
        #else
        return nil
        #endif
    }
}
