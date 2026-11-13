"""Exercise real Pymunk contacts, including readiness after contact begins."""

from __future__ import annotations

import unittest
from unittest.mock import patch

from src.core.versus import BALL_TYPE, LANE_BOTTOM, LANE_BOXES, LANE_TOP, LANE_TYPE, _VersusWorld


def isolated_world(gravity: float = 0.0, radius: float = 5.5, max_speed: float = 900.0) -> _VersusWorld:
    """Omit the unrelated starting crowd while retaining the real space and walls."""
    config = {
        "simulation": {"seed": 42, "gravity": gravity, "release_at": 100.0, "ball_radius": radius, "max_speed": max_speed},
        "versus": {
            "lane_capacity": 100, "seed_balls": 0, "left_burst": 2, "right_burst": 2,
            "left_cooldown": 0.25, "right_cooldown": 0.25, "split_hitstop": 0.0,
        },
    }
    with patch.object(_VersusWorld, "_seed"):
        return _VersusWorld(config)


def add_ball(world: _VersusWorld, position: tuple[float, float], velocity: tuple[float, float], side: str = "left", ready: bool = True) -> dict:
    """Set eligibility explicitly so a random initial timer cannot mask contacts."""
    ball = world._make_ball(side, position, velocity)
    ball["last_birth"] = world.motion_time - world.cooldown[side] - 1.0 if ready else world.motion_time
    return ball


def observe_contacts(world: _VersusWorld) -> list:
    """Record solver-provided arbiters without replacing the production callbacks."""
    contacts = []

    def after_solve(arbiter, _space, _data):
        contacts.append((world.motion_time, tuple(arbiter.shapes), arbiter.is_first_contact))

    world.space.on_collision(BALL_TYPE, LANE_TYPE, post_solve=after_solve)
    world.space.on_collision(BALL_TYPE, BALL_TYPE, post_solve=after_solve)
    return contacts


def split_events(world: _VersusWorld) -> list:
    """Return production split records, including their actual parent IDs."""
    return [event for event in world.event_log if event["type"] == "split"]


class VersusContactTests(unittest.TestCase):
    """A wall and another ball must use the same physical-contact trigger."""

    def test_ready_ball_splits_on_every_lane_boundary(self) -> None:
        """Both lanes' floors, ceilings and side walls produce real splits."""
        for side, (x0, x1) in LANE_BOXES.items():
            center = (x0 + x1) / 2.0
            cases = {
                "floor": ((center, LANE_BOTTOM - 20.0), (0.0, 240.0)),
                "ceiling": ((center, LANE_TOP + 20.0), (0.0, -240.0)),
                "left_wall": ((x0 + 20.0, 700.0), (-240.0, 0.0)),
                "right_wall": ((x1 - 20.0, 700.0), (240.0, 0.0)),
            }
            for boundary, (position, velocity) in cases.items():
                with self.subTest(side=side, boundary=boundary):
                    world = isolated_world()
                    contacts = observe_contacts(world)
                    ball = add_ball(world, position, velocity, side=side)
                    for _ in range(30):
                        world.advance()
                        if not ball["active"]:
                            break
                    self.assertTrue(contacts, "the fixture must actually hit a wall")
                    self.assertFalse(ball["active"])
                    self.assertEqual([event["parent"] for event in split_events(world)], [ball["slot"]])
                    self.assertEqual(world.count[side], 2)

    def test_ball_collision_replaces_both_ready_parents(self) -> None:
        """Two eligible incoming balls are each replaced, in one solver step."""
        world = isolated_world()
        contacts = observe_contacts(world)
        first = add_ball(world, (180.0, 700.0), (120.0, 0.0))
        second = add_ball(world, (200.0, 700.0), (-120.0, 0.0))
        for _ in range(30):
            world.advance()
            if not first["active"]:
                break
        self.assertTrue(contacts)
        self.assertFalse(first["active"])
        self.assertFalse(second["active"])
        events = split_events(world)
        self.assertEqual({event["parent"] for event in events}, {first["slot"], second["slot"]})
        self.assertEqual(len({event["time"] for event in events}), 1)
        self.assertEqual(world.retired_count, 2)
        self.assertEqual(world.count["left"], 4)

    def test_fast_small_balls_do_not_tunnel_through_each_other(self) -> None:
        """A 900 px/s head-on pair must collide even when one outer step swaps it."""
        world = isolated_world(radius=3.0, max_speed=900.0)
        contacts = observe_contacts(world)
        first = add_ball(world, (190.0, 500.0), (900.0, 0.0))
        second = add_ball(world, (197.0, 500.0), (-900.0, 0.0))
        for _ in range(2):
            world.advance()
        self.assertTrue(contacts, "a fast pair must not cross without a solver contact")
        self.assertFalse(first["active"])
        self.assertFalse(second["active"])
        self.assertEqual({event["parent"] for event in split_events(world)}, {first["slot"], second["slot"]})

    def test_fast_grazing_balls_do_not_skip_the_contact(self) -> None:
        """A diagonal near miss at frame endpoints still intersects between them."""
        world = isolated_world(radius=5.5, max_speed=900.0)
        contacts = observe_contacts(world)
        first = add_ball(world, (190.0, 500.0), (900.0, 0.0))
        second = add_ball(world, (197.5, 510.0), (-900.0, 0.0))
        for _ in range(2):
            world.advance()
        self.assertTrue(contacts, "the 10 px closest approach is inside the 11 px combined radius")
        self.assertFalse(first["active"])
        self.assertFalse(second["active"])
        self.assertEqual({event["parent"] for event in split_events(world)}, {first["slot"], second["slot"]})

    def test_unready_collision_partner_still_bounces_without_splitting(self) -> None:
        """Readiness belongs to each ball; an eligible partner does not bypass it."""
        world = isolated_world()
        contacts = observe_contacts(world)
        first = add_ball(world, (180.0, 700.0), (120.0, 0.0))
        second = add_ball(world, (200.0, 700.0), (-120.0, 0.0), ready=False)
        for _ in range(30):
            world.advance()
            if not first["active"]:
                break
        self.assertTrue(contacts)
        self.assertFalse(first["active"])
        self.assertTrue(second["active"])
        self.assertGreater(second["body"].velocity.x, 0.0)
        self.assertEqual([event["parent"] for event in split_events(world)], [first["slot"]])

    def test_same_step_corner_contact_splits_the_parent_once(self) -> None:
        """Hitting a floor and wall together must not replace one ID twice."""
        world = isolated_world()
        contacts = observe_contacts(world)
        ball = add_ball(world, (LANE_BOXES["left"][0] + 8.75, LANE_BOTTOM - 8.75), (-120.0, 120.0))
        world.advance()
        touched_walls = {shape for _time, shapes, _first in contacts for shape in shapes if shape.collision_type == LANE_TYPE}
        self.assertEqual(len(touched_walls), 2, "the solver must report both corner surfaces")
        self.assertEqual([event["parent"] for event in split_events(world)], [ball["slot"]])
        self.assertEqual(world.retired_count, 1)
        self.assertEqual(world.count["left"], 2)

    def test_release_disables_splitting_for_wall_and_ball_contacts(self) -> None:
        """Open walls let balls through; ball collisions continue without division."""
        for kind in ("wall", "ball"):
            with self.subTest(kind=kind):
                world = isolated_world()
                world._release()
                contacts = observe_contacts(world)
                if kind == "wall":
                    balls = [add_ball(world, (LANE_BOXES["left"][0] + 20.0, 700.0), (-240.0, 0.0))]
                else:
                    balls = [add_ball(world, (180.0, 700.0), (120.0, 0.0)), add_ball(world, (200.0, 700.0), (-120.0, 0.0))]
                for _ in range(20):
                    world.advance()
                self.assertEqual(split_events(world), [])
                self.assertTrue(all(ball["active"] for ball in balls))
                if kind == "wall":
                    self.assertLess(balls[0]["body"].position.x, LANE_BOXES["left"][0])
                else:
                    self.assertTrue(contacts)
                    self.assertLess(balls[0]["body"].velocity.x, 0.0)

    def test_floor_contact_is_not_lost_when_ball_becomes_ready(self) -> None:
        """A contact that began during cooldown must be rechecked when ready."""
        world = isolated_world(gravity=260.0)
        contacts = observe_contacts(world)
        ball = add_ball(world, (180.0, LANE_BOTTOM - 8.5), (0.0, 0.0), ready=False)
        ball["shape"].elasticity = 0.0
        for wall in world.walls:
            wall.elasticity = 0.0
        for _ in range(20):
            world.advance()
        self.assertTrue(contacts, "the ball must already be resting in a real floor contact")
        self.assertTrue(ball["active"], "the initial contact occurs before readiness")
        for _ in range(40):
            world.advance()
            if not ball["active"]:
                break
        self.assertTrue(any(time + 1e-8 >= 0.25 and not first for time, _shapes, first in contacts))
        self.assertFalse(ball["active"], "begin-only handling loses a floor contact after cooldown expires")
        self.assertEqual([event["parent"] for event in split_events(world)], [ball["slot"]])
        self.assertEqual(world.retired_count, 1)
        self.assertEqual(world.count["left"], 2)

    def test_protected_ball_does_not_split_after_separating_from_wall(self) -> None:
        """An early bounce cannot become a delayed split after contact has ended."""
        world = isolated_world()
        contacts = observe_contacts(world)
        ball = world._make_ball("left", (LANE_BOXES["left"][0] + 20.0, 700.0), (-240.0, 0.0))
        for _ in range(24):
            world.advance()
        self.assertTrue(contacts, "the protected ball must actually hit the wall")
        self.assertLess(max(time for time, _shapes, _first in contacts), world.cooldown["left"])
        self.assertGreater(ball["body"].velocity.x, 0.0, "the wall must have bounced the ball away")
        self.assertEqual(split_events(world), [])
        for _ in range(36):
            world.advance()
        self.assertGreater(world.motion_time - ball["last_birth"], world.cooldown["left"])
        current_contacts = []
        ball["body"].each_arbiter(lambda arbiter: current_contacts.append(tuple(arbiter.shapes)))
        self.assertEqual(current_contacts, [])
        self.assertTrue(ball["active"])
        self.assertEqual(split_events(world), [], "expired protection cannot manufacture a contact")

    def test_newborns_share_the_full_protection_period(self) -> None:
        """Actual newborns retain their birth clock and split together once ready."""
        world = isolated_world(gravity=260.0)
        contacts = observe_contacts(world)
        balls = [
            world._make_ball(side, ((x0 + x1) / 2.0, LANE_BOTTOM - 8.5), (0.0, 0.0))
            for side, (x0, x1) in LANE_BOXES.items()
        ]
        for ball in balls:
            self.assertEqual(ball["last_birth"], world.motion_time)
            ball["shape"].elasticity = 0.0
        for wall in world.walls:
            wall.elasticity = 0.0
        for _ in range(20):
            world.advance()
        self.assertTrue(all(ball["active"] for ball in balls))
        self.assertEqual(split_events(world), [])
        for ball in balls:
            self.assertTrue(any(ball["shape"] in shapes for _time, shapes, _first in contacts))
        for _ in range(40):
            world.advance()
            if all(not ball["active"] for ball in balls):
                break
        events = split_events(world)
        self.assertEqual({event["parent"] for event in events}, {ball["slot"] for ball in balls})
        self.assertEqual(len(events), 2)
        self.assertEqual(len({event["time"] for event in events}), 1)
        self.assertGreaterEqual(events[0]["time"], 0.25)
        self.assertLessEqual(events[0]["time"], 0.25 + world.fixed_dt + 1e-6)
        self.assertEqual(world.retired_count, 2)
        self.assertEqual(world.count, {"left": 2, "right": 2})


if __name__ == "__main__":
    unittest.main()
