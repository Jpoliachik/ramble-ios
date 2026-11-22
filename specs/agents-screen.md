# Agents screen

## Purpose
What the person sees and does on Settings → "Your agent": one card per connected agent, naming agents, connecting another, spotting an old duplicate, and disconnecting. How agents connect and what they receive is in [delivery.md](delivery.md); the HTTP contract is in [relay-api.md](relay-api.md).

## Cards

### Requirement: Agent cards show name, status and last check-in
The agent screen SHALL be titled "Your agent" ("Your agents" with more than one) and give each agent a card headed by its name: the person's own name for it if they set one, else the name the agent gave ([relay-api.md](relay-api.md)), else "Agent". Under the name: a dot with "Connected" (green) or "Hasn't checked in" (amber), and a line such as "Checked in 2m ago · nothing waiting", "Hasn't checked in yet · nothing waiting", or "Last checked in 14h ago · 2 waiting" when something is waiting. It is "Hasn't checked in" when a copy waits for it and it has not checked its inbox in 12 hours, or ever. Dialogs and the note screen use the same name.

#### Scenario: A quiet agent
- GIVEN 2 notes have waited for the agent and it last checked in 14 hours ago
- WHEN the person opens "Your agent"
- THEN the card is amber and reads "Hasn't checked in" and "Last checked in 14h ago · 2 waiting"
- AND it shows "If your agent lost its setup, connect it again with a fresh message." with a "Connect again" button

### Requirement: Each card has a menu to rename or disconnect
Each card SHALL have a "⋯" button (accessibility label "More for <name>") opening "Rename" and "Disconnect" (red). Disconnect asks first, with the wording below.

## Naming

### Requirement: The person can name each agent
"Rename" SHALL open an alert titled "Rename agent" with "Only you see this name. Leave it empty to use “<the agent's own name, or Agent>”." and a text field holding the person's current name for it (empty if none), with "Cancel" and "Save". Saving stores the name on the relay, trimmed and cut to 40 characters; saving it empty removes it, so the agent's own name shows again. The agent can't see or change the person's name, and an agent renaming itself doesn't replace it.

#### Scenario: Naming the second Claude
- GIVEN two agents both named "Claude" are connected
- WHEN the person renames one to "Claude at work"
- THEN its card, its disconnect dialog and the note screen's agent rows read "Claude at work", and the other still reads "Claude"

#### Scenario: Back to the agent's own name
- GIVEN the person named an agent "Work"
- WHEN they rename it and save the field empty
- THEN the card shows the name the agent gave itself

## More than one agent

### Requirement: Connecting another agent sits under the cards
While fewer than 10 agents are connected, the screen SHALL show a full-width "Connect another agent" row with a plus icon directly under the cards: amber text in a dashed outline, no fill. It opens the Connect screen ([delivery.md](delivery.md)). "Connect another agent" and "Connect again" each pair a separate connection; an existing one stays until disconnected. With more than one agent the bottom action reads "Disconnect all".

#### Scenario: One agent
- GIVEN only "Muse" is connected
- WHEN the person opens "Your agent"
- THEN "Connect another agent" sits right under Muse's card

### Requirement: An old duplicate offers to remove itself
A card SHALL read "Not checking in" with a grey dot, "Looks like an older <name>. It hasn't checked in since <name> connected again." and a red "Remove this one" button, in place of the quiet-agent message, when a newer connection gave the same name, the newer one has checked in, and this one hasn't checked in since the newer one connected. Nothing is removed until the person confirms.

#### Scenario: Claude signed in twice
- GIVEN "Claude" connected on Nov 1 and last checked in on Nov 20, and another "Claude" connected on Nov 22 and has checked in
- WHEN the person opens "Your agents"
- THEN the Nov 1 card offers "Remove this one", and the Nov 22 card reads "Connected"

## Disconnecting

### Requirement: Disconnect cuts an agent off at once
Disconnecting an agent SHALL revoke its key immediately, delete every copy waiting for it, and remove its wake-up hook. Other agents stay connected.

#### Scenario: Disconnect one of two
- GIVEN "Grok Bot" has 3 notes waiting and "Muse" has 1
- WHEN the person disconnects "Grok Bot"
- THEN Grok Bot's 3 copies are deleted and its key stops working
- AND Muse's copy is untouched

### Requirement: Disconnect asks first
The app SHALL confirm before disconnecting: "Disconnect your agent?" with "It loses access immediately, and anything waiting for it is deleted." for a single agent; "Disconnect <name>?" with "It loses access immediately, and anything waiting for it is deleted. Your other agents stay connected." for one of several; "Disconnect your agents?" with "They lose access immediately, and anything waiting for them is deleted." for "Disconnect all".

#### Scenario: Disconnect all
- GIVEN two agents are connected
- WHEN the person taps "Disconnect all"
- THEN "Disconnect your agents?" appears, and nothing changes until they confirm
