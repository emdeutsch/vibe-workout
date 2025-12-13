import ClockKit
import SwiftUI

class ComplicationController: NSObject, CLKComplicationDataSource {

    // MARK: - Timeline Configuration

    func getPrivacyBehavior(
        for complication: CLKComplication,
        withHandler handler: @escaping (CLKComplicationPrivacyBehavior) -> Void
    ) {
        // Show HR data even on locked watch (user preference)
        handler(.showOnLockScreen)
    }

    func getComplicationDescriptors(
        handler: @escaping ([CLKComplicationDescriptor]) -> Void
    ) {
        let descriptors = [
            CLKComplicationDescriptor(
                identifier: "viberunner_hr",
                displayName: "Heart Rate",
                supportedFamilies: [
                    .circularSmall,
                    .modularSmall,
                    .modularLarge,
                    .utilitarianSmall,
                    .utilitarianSmallFlat,
                    .utilitarianLarge,
                    .graphicCorner,
                    .graphicCircular,
                    .graphicRectangular,
                    .graphicExtraLarge
                ]
            ),
            CLKComplicationDescriptor(
                identifier: "viberunner_status",
                displayName: "Workout Status",
                supportedFamilies: [
                    .circularSmall,
                    .modularSmall,
                    .graphicCorner,
                    .graphicCircular
                ]
            )
        ]
        handler(descriptors)
    }

    // MARK: - Timeline Population

    func getCurrentTimelineEntry(
        for complication: CLKComplication,
        withHandler handler: @escaping (CLKComplicationTimelineEntry?) -> Void
    ) {
        let template = makeTemplate(for: complication)
        if let template = template {
            let entry = CLKComplicationTimelineEntry(
                date: Date(),
                complicationTemplate: template
            )
            handler(entry)
        } else {
            handler(nil)
        }
    }

    func getTimelineEntries(
        for complication: CLKComplication,
        after date: Date,
        limit: Int,
        withHandler handler: @escaping ([CLKComplicationTimelineEntry]?) -> Void
    ) {
        // We update in real-time, no future entries needed
        handler(nil)
    }

    // MARK: - Template Creation

    private func makeTemplate(for complication: CLKComplication) -> CLKComplicationTemplate? {
        let workoutManager = WorkoutManager.shared
        let bpm = workoutManager.currentHeartRate
        let isActive = workoutManager.isWorkoutActive
        let hrOk = bpm >= workoutManager.threshold

        switch complication.family {
        case .circularSmall:
            return makeCircularSmallTemplate(bpm: bpm, isActive: isActive, hrOk: hrOk)
        case .modularSmall:
            return makeModularSmallTemplate(bpm: bpm, isActive: isActive, hrOk: hrOk)
        case .modularLarge:
            return makeModularLargeTemplate(bpm: bpm, isActive: isActive, hrOk: hrOk)
        case .utilitarianSmall, .utilitarianSmallFlat:
            return makeUtilitarianSmallTemplate(bpm: bpm, isActive: isActive)
        case .utilitarianLarge:
            return makeUtilitarianLargeTemplate(bpm: bpm, isActive: isActive, hrOk: hrOk)
        case .graphicCorner:
            return makeGraphicCornerTemplate(bpm: bpm, isActive: isActive, hrOk: hrOk)
        case .graphicCircular:
            return makeGraphicCircularTemplate(bpm: bpm, isActive: isActive, hrOk: hrOk)
        case .graphicRectangular:
            return makeGraphicRectangularTemplate(bpm: bpm, isActive: isActive, hrOk: hrOk)
        case .graphicExtraLarge:
            return makeGraphicExtraLargeTemplate(bpm: bpm, isActive: isActive, hrOk: hrOk)
        default:
            return nil
        }
    }

    // MARK: - Circular Small

    private func makeCircularSmallTemplate(bpm: Int, isActive: Bool, hrOk: Bool) -> CLKComplicationTemplate {
        let template = CLKComplicationTemplateCircularSmallStackImage(
            line1ImageProvider: CLKImageProvider(onePieceImage: UIImage(systemName: "heart.fill")!),
            line2TextProvider: CLKSimpleTextProvider(text: "\(bpm)")
        )
        template.tintColor = hrOk ? .green : .red
        return template
    }

    // MARK: - Modular Small

    private func makeModularSmallTemplate(bpm: Int, isActive: Bool, hrOk: Bool) -> CLKComplicationTemplate {
        let template = CLKComplicationTemplateModularSmallStackImage(
            line1ImageProvider: CLKImageProvider(onePieceImage: UIImage(systemName: "heart.fill")!),
            line2TextProvider: CLKSimpleTextProvider(text: "\(bpm)")
        )
        template.tintColor = hrOk ? .green : .red
        return template
    }

    // MARK: - Modular Large

    private func makeModularLargeTemplate(bpm: Int, isActive: Bool, hrOk: Bool) -> CLKComplicationTemplate {
        let statusText = isActive ?
            (hrOk ? "Tools Unlocked" : "Tools Locked") :
            "No Workout"

        return CLKComplicationTemplateModularLargeTallBody(
            headerTextProvider: CLKSimpleTextProvider(text: "viberunner"),
            bodyTextProvider: CLKSimpleTextProvider(text: "\(bpm) BPM - \(statusText)")
        )
    }

    // MARK: - Utilitarian Small

    private func makeUtilitarianSmallTemplate(bpm: Int, isActive: Bool) -> CLKComplicationTemplate {
        return CLKComplicationTemplateUtilitarianSmallFlat(
            textProvider: CLKSimpleTextProvider(text: "♥ \(bpm)")
        )
    }

    // MARK: - Utilitarian Large

    private func makeUtilitarianLargeTemplate(bpm: Int, isActive: Bool, hrOk: Bool) -> CLKComplicationTemplate {
        let statusEmoji = hrOk ? "✓" : "✗"
        return CLKComplicationTemplateUtilitarianLargeFlat(
            textProvider: CLKSimpleTextProvider(text: "♥ \(bpm) BPM \(statusEmoji)")
        )
    }

    // MARK: - Graphic Corner

    private func makeGraphicCornerTemplate(bpm: Int, isActive: Bool, hrOk: Bool) -> CLKComplicationTemplate {
        let gaugeProvider = CLKSimpleGaugeProvider(
            style: .fill,
            gaugeColor: hrOk ? .green : .red,
            fillFraction: min(1.0, Float(bpm) / 200.0)
        )

        return CLKComplicationTemplateGraphicCornerGaugeText(
            gaugeProvider: gaugeProvider,
            outerTextProvider: CLKSimpleTextProvider(text: "\(bpm)")
        )
    }

    // MARK: - Graphic Circular

    private func makeGraphicCircularTemplate(bpm: Int, isActive: Bool, hrOk: Bool) -> CLKComplicationTemplate {
        let gaugeProvider = CLKSimpleGaugeProvider(
            style: .ring,
            gaugeColor: hrOk ? .green : .red,
            fillFraction: min(1.0, Float(bpm) / 200.0)
        )

        return CLKComplicationTemplateGraphicCircularClosedGaugeText(
            gaugeProvider: gaugeProvider,
            centerTextProvider: CLKSimpleTextProvider(text: "\(bpm)")
        )
    }

    // MARK: - Graphic Rectangular

    private func makeGraphicRectangularTemplate(bpm: Int, isActive: Bool, hrOk: Bool) -> CLKComplicationTemplate {
        let headerText = isActive ? "viberunner Active" : "viberunner"
        let statusText = isActive ?
            (hrOk ? "Tools Unlocked ✓" : "Tools Locked ✗") :
            "Start a workout"

        return CLKComplicationTemplateGraphicRectangularStandardBody(
            headerTextProvider: CLKSimpleTextProvider(text: headerText),
            body1TextProvider: CLKSimpleTextProvider(text: "\(bpm) BPM"),
            body2TextProvider: CLKSimpleTextProvider(text: statusText)
        )
    }

    // MARK: - Graphic Extra Large

    private func makeGraphicExtraLargeTemplate(bpm: Int, isActive: Bool, hrOk: Bool) -> CLKComplicationTemplate {
        let gaugeProvider = CLKSimpleGaugeProvider(
            style: .ring,
            gaugeColor: hrOk ? .green : .red,
            fillFraction: min(1.0, Float(bpm) / 200.0)
        )

        return CLKComplicationTemplateGraphicExtraLargeCircularClosedGaugeText(
            gaugeProvider: gaugeProvider,
            centerTextProvider: CLKSimpleTextProvider(text: "\(bpm)")
        )
    }
}

// MARK: - Complication Reload Helper

extension ComplicationController {
    static func reloadComplications() {
        let server = CLKComplicationServer.sharedInstance()
        for complication in server.activeComplications ?? [] {
            server.reloadTimeline(for: complication)
        }
    }
}
