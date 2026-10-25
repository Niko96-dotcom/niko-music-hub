import Darwin
import Foundation

final class ProjectVaultMutationFileLease: @unchecked Sendable {
    private var descriptor: Int32

    init(url: URL) throws {
        descriptor = Darwin.open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw ProjectVaultRuntimeError.mutationLockUnavailable(errno)
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            Darwin.close(descriptor)
            descriptor = -1
            if code == EWOULDBLOCK || code == EAGAIN {
                throw ProjectVaultRuntimeError.mutationInProgress
            }
            throw ProjectVaultRuntimeError.mutationLockUnavailable(code)
        }
    }

    func release() {
        guard descriptor >= 0 else { return }
        _ = flock(descriptor, LOCK_UN)
        Darwin.close(descriptor)
        descriptor = -1
    }

    deinit {
        release()
    }
}
