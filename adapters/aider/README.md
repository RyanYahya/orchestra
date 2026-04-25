# Aider Integration

Aider does not support custom slash commands the same way other tools do, but you
can still drive the orchestra prompts manually:

```
/read .orchestra/prompts/plan.md
```

Then describe your task. Aider will follow the prompt body.

Or alias via shell:

```bash
alias plan='aider --message "$(cat .orchestra/prompts/plan.md)"'
```
