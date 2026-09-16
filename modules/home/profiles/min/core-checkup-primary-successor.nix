{ lib, ... }:

# Deployment-scoped source proposal for the primary Claude successor. A
# secondary activation imports this module as part of its Home configuration.
# The two target lists are a fresh snapshot: the predecessor `primary-840e42`
# is deliberately absent, while the known secondary and Codex targets remain
# present. `mkForce` replaces each complete list, so an activator must reconcile
# any newer target into this snapshot before using it. This module does not
# enable the timer, choose a roster, install a generation, or restart a service.
{
  criomosHome.coreCheckup = {
    codexTargets = lib.mkForce [
      {
        identifier = "cf7879";
        threadId = "01a0a715-2d5d-7342-b278-1dbcf78795bd";
        socketPath = "$HOME/.codex/app-server-control/app-server-control.sock";
        openWork = true;
      }
      {
        identifier = "e43002";
        threadId = "01a0a792-2d0e-7a53-ac0b-9b3e43002941";
        socketPath = "$HOME/.codex/app-server-control/app-server-control.sock";
        openWork = true;
      }
    ];
    claudeTargets = lib.mkForce [
      {
        identifier = "primary-claude-successor-840e42";
        sessionId = "efa15708-dc5d-42ce-af62-8ffb84c9815e";
        transcriptPath = "/home/li/.claude/projects/-home-li-wt-github-com-LiGoldragon-primary-claude-successor-840e42-bootstrap-local--claude-worktrees-claude-successor-840e42/efa15708-dc5d-42ce-af62-8ffb84c9815e.jsonl";
        openWork = true;
      }
      {
        identifier = "secondary-57a7aa";
        sessionId = "57a7aa02-e52d-4266-8746-6770ff770d11";
        transcriptPath = "/home/li/.claude/projects/-git-github-com-LiGoldragon-secondary/57a7aa02-e52d-4266-8746-6770ff770d11.jsonl";
        openWork = true;
      }
    ];
  };
}
