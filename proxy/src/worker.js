// Worker entry point. The Workers runtime treats every named export of the
// entry module as an entrypoint and rejects anything that isn't a handler
// (`wrangler dev` refuses to start otherwise), so the entry re-exports only
// the default handler. index.js keeps its named exports for the tests.
export { default } from './index.js';
