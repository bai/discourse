import { censorFn } from "pretty-text/censored-words";

function recurse(tokens, apply) {
  let i;
  for (i = 0; i < tokens.length; i++) {
    if (tokens[i].type === "html_raw" && tokens[i].onebox) {
      continue;
    }

    apply(tokens[i]);
    if (tokens[i].children) {
      recurse(tokens[i].children, apply);
    }
  }
}

function censorTree(state, censor) {
  if (!state.tokens) {
    return;
  }

  recurse(state.tokens, (token) => {
    if (token.content) {
      token.content = censor(token.content);
    }
  });
}

export function setup(helper) {
  helper.registerOptions((opts, siteSettings) => {
    opts.watchedWordsRegularExpressions =
      siteSettings.watched_words_regular_expressions;
  });

  helper.registerPlugin((md) => {
    const censoredRegexp = md.options.discourse.censoredRegexp;

    if (censoredRegexp) {
      const replacement = String.fromCharCode(9632);
      const censor = censorFn(censoredRegexp, replacement);
      md.core.ruler.push("censored", (state) => censorTree(state, censor));
    }
  });
}
