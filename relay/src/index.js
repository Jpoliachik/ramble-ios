// Worker entry point. The runtime treats every named export of this module as
// an entrypoint and rejects non-functions, so the implementation — and the
// constants and helpers tests import — live in relay.js.
export { default } from './relay.js';
