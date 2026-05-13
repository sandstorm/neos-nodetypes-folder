@flowEntities @contentrepository
Feature: A dimension variant of a folder-child gets its own URL in the new dimension

  When an editor creates a language variant of a page that sits under a
  transparent folder, the new variant must build its URL against the new
  dimension's parent chain — applying that dimension's URL prefix, and
  preserving folder transparency there too. The original dimension's URL
  must keep working independently.

  Renaming the variant's segment in one dimension must not corrupt the URL
  in the other dimension.

  Starts in DE dimension only; EN variants are created via CreateNodeVariant:

      lady-eleonode-rootford
      └─ site-of-folders         (Test.Routing.Page, name "node1", segment "site-ignored")
         └─ folder-a              (Folder, hide=true, segment "folder-a")
            └─ child-in-folder    (Test.Routing.Page, segment "child")

  Background:
    Given using the following content dimensions:
      | Identifier | Values | Generalizations |
      | language   | de, en | en->de          |
    And using the following node types:
    """yaml
    'Neos.Neos:Sites':
      superTypes:
        'Neos.ContentRepository:Root': true
    'Neos.Neos:Document': {}
    'Neos.Neos:Content': {}
    'Neos.Neos:Test.Routing.Page':
      superTypes:
        'Neos.Neos:Document': true
      properties:
        uriPathSegment:
          type: string
    'Sandstorm.NodeTypes.Folder:Mixin.HideUriSegment':
      abstract: true
      properties:
        hideSegmentInUriPath:
          type: boolean
          defaultValue: true
    'Sandstorm.NodeTypes.Folder:Document.Folder':
      superTypes:
        'Neos.Neos:Document': true
        'Sandstorm.NodeTypes.Folder:Mixin.HideUriSegment': true
      properties:
        uriPathSegment:
          type: string
    """
    And using identifier "default", I define a content repository
    And I am in content repository "default"
    And I am user identified by "initiating-user-identifier"
    When the command CreateRootWorkspace is executed with payload:
      | Key                | Value           |
      | workspaceName      | "live"          |
      | newContentStreamId | "cs-identifier" |
    And I am in workspace "live" and dimension space point {"language": "de"}
    And the command CreateRootNodeAggregateWithNode is executed with payload:
      | Key             | Value                    |
      | nodeAggregateId | "lady-eleonode-rootford" |
      | nodeTypeName    | "Neos.Neos:Sites"        |
    And the following CreateNodeAggregateWithNode commands are executed:
      | nodeAggregateId | parentNodeAggregateId  | nodeTypeName                                  | initialPropertyValues                                          | nodeName |
      | site-of-folders | lady-eleonode-rootford | Neos.Neos:Test.Routing.Page                   | {"uriPathSegment": "site-ignored"}                             | node1    |
      | folder-a        | site-of-folders        | Sandstorm.NodeTypes.Folder:Document.Folder    | {"uriPathSegment": "folder-a", "hideSegmentInUriPath": true}   | folderA  |
      | child-in-folder | folder-a               | Neos.Neos:Test.Routing.Page                   | {"uriPathSegment": "child"}                                    | child    |
    And A site exists for node name "node1"
    And the sites configuration is:
    """yaml
    Neos:
      Neos:
        sites:
          'node1':
            preset: 'default'
            uriPathSuffix: ''
            contentDimensions:
              defaultDimensionSpacePoint:
                language: de
              resolver:
                factoryClassName: Neos\Neos\FrontendRouting\DimensionResolution\Resolver\UriPathResolverFactory
                options:
                  segments:
                    -
                      dimensionIdentifier: language
                      dimensionValueMapping:
                        de: ''
                        en: en
    """

  Scenario: DE baseline — folder is transparent, child resolves at the root
    When I am on URL "/"
    Then the node "child-in-folder" in dimension '{"language":"de"}' should resolve to URL "/child"
    When I am on URL "/child"
    Then the matched node should be "child-in-folder" in dimension '{"language":"de"}'

  Scenario: CreateNodeVariant rebuilds the EN row with EN folder transparency (PR #3 #1 + #2)
    When the command CreateNodeVariant is executed with payload:
      | Key             | Value             |
      | nodeAggregateId | "site-of-folders" |
      | sourceOrigin    | {"language":"de"} |
      | targetOrigin    | {"language":"en"} |
    And the command CreateNodeVariant is executed with payload:
      | Key             | Value             |
      | nodeAggregateId | "folder-a"        |
      | sourceOrigin    | {"language":"de"} |
      | targetOrigin    | {"language":"en"} |
    And the command CreateNodeVariant is executed with payload:
      | Key             | Value             |
      | nodeAggregateId | "child-in-folder" |
      | sourceOrigin    | {"language":"de"} |
      | targetOrigin    | {"language":"en"} |
    And I am on URL "/"
    Then the node "child-in-folder" in dimension '{"language":"en"}' should resolve to URL "/en/child"
    And the node "child-in-folder" in dimension '{"language":"de"}' should resolve to URL "/child"
    When I am on URL "/en/child"
    Then the matched node should be "child-in-folder" in dimension '{"language":"en"}'

  Scenario: Renaming uriPathSegment in EN does not corrupt DE
    When the command CreateNodeVariant is executed with payload:
      | Key             | Value             |
      | nodeAggregateId | "site-of-folders" |
      | sourceOrigin    | {"language":"de"} |
      | targetOrigin    | {"language":"en"} |
    And the command CreateNodeVariant is executed with payload:
      | Key             | Value             |
      | nodeAggregateId | "folder-a"        |
      | sourceOrigin    | {"language":"de"} |
      | targetOrigin    | {"language":"en"} |
    And the command CreateNodeVariant is executed with payload:
      | Key             | Value             |
      | nodeAggregateId | "child-in-folder" |
      | sourceOrigin    | {"language":"de"} |
      | targetOrigin    | {"language":"en"} |
    And the command SetNodeProperties is executed with payload:
      | Key                       | Value                          |
      | nodeAggregateId           | "child-in-folder"              |
      | originDimensionSpacePoint | {"language":"en"}              |
      | propertyValues            | {"uriPathSegment": "kid-en"}   |
    And I am on URL "/"
    Then the node "child-in-folder" in dimension '{"language":"en"}' should resolve to URL "/en/kid-en"
    And the node "child-in-folder" in dimension '{"language":"de"}' should resolve to URL "/child"
