@flowEntities @contentrepository
Feature: Toggling a folder's visibility is rejected when the toggle would create a URL collision

  Today an opaque folder keeps its descendants in their own URL space:
  /folder-a/widget and /widget can coexist. If an editor flips the folder to
  transparent, those two URLs collapse into the same `/widget`. We catch the
  prospective collision when the toggle is requested and refuse it, rather
  than letting the projection arrive at a state where two nodes resolve to
  the same URL.

  The reverse toggle (transparent → opaque) and toggles on folders whose
  descendants don't collide must continue to work normally.

      lady-eleonode-rootford
      └─ site-of-folders        (Test.Routing.Page, name "node1", segment "site-ignored")
         ├─ folder-a             (Folder, hide=false, segment "folder-a")  ← starts opaque, has /folder-a/widget
         │  └─ widget-in-folder  (Test.Routing.Page, segment "widget")
         └─ widget-at-root       (Test.Routing.Page, segment "widget")     ← already at /widget — flipping folder-a would collide

  Background:
    Given using no content dimensions
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
    And I am in workspace "live" and dimension space point {}
    And the command CreateRootNodeAggregateWithNode is executed with payload:
      | Key             | Value                    |
      | nodeAggregateId | "lady-eleonode-rootford" |
      | nodeTypeName    | "Neos.Neos:Sites"        |
    And the following CreateNodeAggregateWithNode commands are executed:
      | nodeAggregateId   | parentNodeAggregateId  | nodeTypeName                                  | initialPropertyValues                                          | nodeName |
      | site-of-folders   | lady-eleonode-rootford | Neos.Neos:Test.Routing.Page                   | {"uriPathSegment": "site-ignored"}                             | node1    |
      | folder-a          | site-of-folders        | Sandstorm.NodeTypes.Folder:Document.Folder    | {"uriPathSegment": "folder-a", "hideSegmentInUriPath": false}  | folderA  |
      | widget-in-folder  | folder-a               | Neos.Neos:Test.Routing.Page                   | {"uriPathSegment": "widget"}                                   | wInF     |
      | widget-at-root    | site-of-folders        | Neos.Neos:Test.Routing.Page                   | {"uriPathSegment": "widget"}                                   | wAtR     |
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
              resolver:
                factoryClassName: Neos\Neos\FrontendRouting\DimensionResolution\Resolver\NoopResolverFactory
    """

  Scenario: Toggling the folder to transparent is rejected when a descendant would collide
    When the command SetNodeProperties is executed with payload and exceptions are caught:
      | Key                       | Value                              |
      | nodeAggregateId           | "folder-a"                         |
      | originDimensionSpacePoint | {}                                 |
      | propertyValues            | {"hideSegmentInUriPath": true}     |
    Then the last command should have thrown an exception of type "UriPathCollisionDetected"

  Scenario: Toggle without a colliding descendant succeeds
    # Remove the conflicting widget-at-root first; the toggle should then succeed.
    When the command RemoveNodeAggregate is executed with payload:
      | Key                          | Value            |
      | nodeAggregateId              | "widget-at-root" |
      | coveredDimensionSpacePoint   | {}               |
      | nodeVariantSelectionStrategy | "allVariants"    |
    And the command SetNodeProperties is executed with payload:
      | Key                       | Value                          |
      | nodeAggregateId           | "folder-a"                     |
      | originDimensionSpacePoint | {}                             |
      | propertyValues            | {"hideSegmentInUriPath": true} |
    And I am on URL "/"
    Then the node "widget-in-folder" in dimension "{}" should resolve to URL "/widget"
    When I am on URL "/widget"
    Then the matched node should be "widget-in-folder" in dimension "{}"
