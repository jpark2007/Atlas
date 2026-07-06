import XCTest
@testable import AtlasCore

final class InviteFlowTests: XCTestCase {
    func testAcceptedInviteYieldsMemberRole() {
        let invite = InviteRow(id: UUID(), kind: .project, targetId: UUID(),
                               inviterId: UUID(), inviteeEmail: "a@b.com",
                               status: .accepted, createdAt: "2026-01-01T00:00:00Z")
        let membership = InviteRow.membershipIfAccepted(invite, acceptingUserId: UUID())
        XCTAssertNotNil(membership)
        XCTAssertEqual(membership?.role, "member")
    }

    func testDeclinedInviteYieldsNoMembership() {
        let invite = InviteRow(id: UUID(), kind: .project, targetId: UUID(),
                               inviterId: UUID(), inviteeEmail: "a@b.com",
                               status: .declined, createdAt: "2026-01-01T00:00:00Z")
        XCTAssertNil(InviteRow.membershipIfAccepted(invite, acceptingUserId: UUID()))
    }

    func testNonProjectInviteYieldsNoProjectMembership() {
        let invite = InviteRow(id: UUID(), kind: .space, targetId: UUID(),
                               inviterId: UUID(), inviteeEmail: "a@b.com",
                               status: .accepted, createdAt: "2026-01-01T00:00:00Z")
        XCTAssertNil(InviteRow.membershipIfAccepted(invite, acceptingUserId: UUID()))
    }
}
