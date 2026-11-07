import Foundation

protocol MetricSampling: AnyObject {
    func sample() -> Reading
    func refreshDisks(into reading: inout Reading)
    func resetAfterWake()
}
extension Sampler: MetricSampling {}

// Scheduling state and delivery belong to main; the sampler belongs exclusively
// to one worker queue, including its initialization and hardware discovery.
final class SamplingService {
    var onSample: ((Reading, Date, Bool) -> Void)?
    var onDisks: ((Reading) -> Void)?
    private let queue = DispatchQueue(label: "local.Neylu.sampling", qos: .utility)
    private let makeSampler: () -> MetricSampling
    private var sampler: MetricSampling?
    private var busy = false
    private var suspended = false
    private var generation = 0
    private var pendingSample = false
    private var pendingHistory = false
    private var pendingReset = false
    private var pendingDisks = false

    init(makeSampler: @escaping () -> MetricSampling = { Sampler() }) { self.makeSampler = makeSampler }

    func sample(recordHistory: Bool = false) {
        precondition(Thread.isMainThread)
        guard !suspended else { return }
        pendingSample = true
        pendingHistory = pendingHistory || recordHistory
        startNext()
    }
    func refreshDisks() {
        precondition(Thread.isMainThread)
        pendingDisks = true
        startNext()
    }
    func suspend() {
        precondition(Thread.isMainThread)
        generation += 1
        suspended = true
        pendingSample = false
        pendingHistory = false
    }
    func resumeAfterWake() {
        precondition(Thread.isMainThread)
        generation += 1
        suspended = false
        pendingReset = true
        pendingSample = true
        startNext()
    }
    private func startNext() {
        guard !busy, !suspended, pendingSample || pendingDisks else { return }
        busy = true
        let fullSample = pendingSample
        let reset = pendingReset
        let recordHistory = pendingHistory
        let refreshDisks = pendingDisks
        let token = generation
        pendingDisks = false // A full sample also discovers current disks.
        if fullSample { pendingSample = false; pendingHistory = false; pendingReset = false }
        queue.async { [self] in
            if sampler == nil { sampler = makeSampler() }
            let reader = sampler!
            var reading: Reading
            if fullSample {
                if reset { reader.resetAfterWake() }
                reading = reader.sample()
                if refreshDisks { reader.refreshDisks(into: &reading) }
            } else {
                reading = Reading()
                reader.refreshDisks(into: &reading)
            }
            let timestamp = Date()
            let result = reading
            DispatchQueue.main.async { [self] in
                if token == generation, !suspended {
                    if fullSample { onSample?(result, timestamp, recordHistory) }
                    else { onDisks?(result) }
                }
                busy = false
                startNext()
            }
        }
    }
}
