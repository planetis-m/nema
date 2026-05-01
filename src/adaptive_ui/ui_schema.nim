import jsonx
import openai/chat

type
  SchemaProp = object
    `type`: string
    description: string

  SchemaEnumProp = object
    `type`: string
    description: string
    `enum`: seq[string]

  UiOptionSchema = object
    `type`: string
    properties: tuple[
      id: SchemaProp,
      label: SchemaProp,
      selected: SchemaProp
    ]
    required: seq[string]
    additionalProperties: bool

  UiOptionArraySchema = object
    `type`: string
    description: string
    items: UiOptionSchema

  UiAreaSchema = object
    `type`: string
    properties: tuple[
      name: SchemaProp,
      kind: SchemaEnumProp,
      text: SchemaProp,
      id: SchemaProp,
      options: UiOptionArraySchema,
      language: SchemaProp,
      placeholder: SchemaProp,
      submitLabel: SchemaProp
    ]
    required: seq[string]
    additionalProperties: bool

  UiAreaArraySchema = object
    `type`: string
    description: string
    items: UiAreaSchema

  UiDocSchema = object
    `type`: string
    properties: tuple[
      version: SchemaProp,
      title: SchemaProp,
      layout: SchemaProp,
      focus: SchemaProp,
      areas: UiAreaArraySchema
    ]
    required: seq[string]
    additionalProperties: bool

let uiDocFmt* = formatJsonSchema("ui_doc", UiDocSchema(
  `type`: "object",
  properties: (
    version: SchemaProp(`type`: "integer", description: "UiDoc version. Must be 1."),
    title: SchemaProp(`type`: "string", description: "Short screen title."),
    layout: SchemaProp(`type`: "string", description: "uirelays markdown table layout."),
    focus: SchemaProp(`type`: "string", description: "Optional focused area name."),
    areas: UiAreaArraySchema(
      `type`: "array",
      description: "Areas rendered into layout cells.",
      items: UiAreaSchema(
        `type`: "object",
        properties: (
          name: SchemaProp(`type`: "string", description: "Layout cell name."),
          kind: SchemaEnumProp(
            `type`: "string",
            description: "One supported UiKind string.",
            `enum`: @["text", "code", "radio", "buttons", "textInput", "math"]
          ),
          text: SchemaProp(`type`: "string", description: "Plain text content."),
          id: SchemaProp(`type`: "string", description: "Stable component id for interactive areas."),
          options: UiOptionArraySchema(
            `type`: "array",
            description: "Options for radio groups and button rows.",
            items: UiOptionSchema(
              `type`: "object",
              properties: (
                id: SchemaProp(`type`: "string", description: "Stable option id."),
                label: SchemaProp(`type`: "string", description: "Visible option label."),
                selected: SchemaProp(`type`: "boolean", description: "Whether this option is selected.")
              ),
              required: @["id", "label"],
              additionalProperties: false
            )
          ),
          language: SchemaProp(`type`: "string", description: "Code language name."),
          placeholder: SchemaProp(`type`: "string", description: "Text input placeholder."),
          submitLabel: SchemaProp(`type`: "string", description: "Text input submit button label.")
        ),
        required: @["name", "kind"],
        additionalProperties: false
      )
    )
  ),
  required: @["version", "title", "layout", "areas"],
  additionalProperties: false
), strict = true)
