@flowEntities @contentrepository
Feature: Creating a dimension variant whose URL would collide in the target dimension is rejected

  Translating a page to a new language creates a variant of the original. The
  variant inherits the original's URL segment, but the URL is rebuilt against
  the target dimension's parent chain. If a different node already occupies
  that URL in the target dimension, we refuse the variant rather than create
  two nodes at the same address.

  Variants that don't collide continue to work and both dimensions resolve
  independently.

  Starts in DE dimension; site/folder/child variants are created into EN, and
  in the collision scenario the EN dimension already has a node sitting where
  the variant would land.

      lady-eleonode-rootford
      └─ site-of-folders         (Test.Routing.Page, name "node1", segment "site-ignored")
         └─ folder-a              (Folder, hide=true, segment "folder-a")
            └─ child-in-folder    (Test.Routing.Page, segment "child")     ← gets a variant in EN

  Background:
    Given using the following content dimensions:
      | Identifier | Values | Generalizations |
      | language   | de, en |                 |
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

  Scenario: Variant succeeds when no collision exists in target dimension
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

  Scenario: Variant is rejected when the target-dimension URL is already taken
    # First, set up the EN dimension with a different node already occupying /en/child.
    When the command CreateNodeVariant is executed with payload:
      | Key             | Value             |
      | nodeAggregateId | "site-of-folders" |
      | sourceOrigin    | {"language":"de"} |
      | targetOrigin    | {"language":"en"} |
    And I am in workspace "live" and dimension space point {"language": "en"}
    And the command CreateNodeAggregateWithNode is executed with payload:
      | Key                       | Value                         |
      | nodeAggregateId           | "blocker-en"                  |
      | parentNodeAggregateId     | "site-of-folders"             |
      | nodeTypeName              | "Neos.Neos:Test.Routing.Page" |
      | originDimensionSpacePoint | {"language": "en"}            |
      | initialPropertyValues     | {"uriPathSegment": "child"}   |
    And I am in workspace "live" and dimension space point {"language": "de"}
    # Now try to copy folder-a + child-in-folder into EN — child would land at /en/child, blocked.
    And the command CreateNodeVariant is executed with payload:
      | Key             | Value             |
      | nodeAggregateId | "folder-a"        |
      | sourceOrigin    | {"language":"de"} |
      | targetOrigin    | {"language":"en"} |
    And the command CreateNodeVariant is executed with payload and exceptions are caught:
      | Key             | Value             |
      | nodeAggregateId | "child-in-folder" |
      | sourceOrigin    | {"language":"de"} |
      | targetOrigin    | {"language":"en"} |
    Then the last command should have thrown an exception of type "UriPathCollisionDetected"
