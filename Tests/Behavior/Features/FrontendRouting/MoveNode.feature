@flowEntities @contentrepository
Feature: Moving a node between transparent / opaque parents recomputes its URL correctly

  Exercises `FolderUriPathLogic::buildParentUriPath()` via the projection's
  `moveNode` branch. Moving a descendant out of a transparent folder must add
  the new parent's segments to its URL; moving into a transparent folder must
  drop them.

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
      | nodeAggregateId | parentNodeAggregateId  | nodeTypeName                                  | initialPropertyValues                                              | nodeName |
      | site-of-folders | lady-eleonode-rootford | Neos.Neos:Test.Routing.Page                   | {"uriPathSegment": "site-ignored"}                                 | node1    |
      | folder-a        | site-of-folders        | Sandstorm.NodeTypes.Folder:Document.Folder    | {"uriPathSegment": "folder-a", "hideSegmentInUriPath": true}       | folderA  |
      | folder-b        | site-of-folders        | Sandstorm.NodeTypes.Folder:Document.Folder    | {"uriPathSegment": "folder-b", "hideSegmentInUriPath": true}       | folderB  |
      | folder-opaque   | site-of-folders        | Sandstorm.NodeTypes.Folder:Document.Folder    | {"uriPathSegment": "visible-folder", "hideSegmentInUriPath": false}| folderO  |
      | mover           | folder-a               | Neos.Neos:Test.Routing.Page                   | {"uriPathSegment": "mover"}                                        | mover    |
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

  Scenario: Moving between two transparent folders keeps the URL flat
    When I am on URL "/"
    And the node "mover" in dimension "{}" should resolve to URL "/mover"
    And the command MoveNodeAggregate is executed with payload:
      | Key                                 | Value      |
      | nodeAggregateId                     | "mover"    |
      | dimensionSpacePoint                 | {}         |
      | newParentNodeAggregateId            | "folder-b" |
      | newSucceedingSiblingNodeAggregateId | null       |
    And I am on URL "/"
    Then the node "mover" in dimension "{}" should resolve to URL "/mover"
    When I am on URL "/mover"
    Then the matched node should be "mover" in dimension "{}"

  Scenario: Moving into an opaque folder adds the folder segment to the URL
    When I am on URL "/"
    And the node "mover" in dimension "{}" should resolve to URL "/mover"
    And the command MoveNodeAggregate is executed with payload:
      | Key                                 | Value           |
      | nodeAggregateId                     | "mover"         |
      | dimensionSpacePoint                 | {}              |
      | newParentNodeAggregateId            | "folder-opaque" |
      | newSucceedingSiblingNodeAggregateId | null            |
    And I am on URL "/"
    Then the node "mover" in dimension "{}" should resolve to URL "/visible-folder/mover"
    When I am on URL "/visible-folder/mover"
    Then the matched node should be "mover" in dimension "{}"
    When I am on URL "/mover"
    Then No node should match URL "/mover"

  Scenario: Moving out of an opaque folder back to a transparent one drops the segment
    When the command MoveNodeAggregate is executed with payload:
      | Key                                 | Value           |
      | nodeAggregateId                     | "mover"         |
      | dimensionSpacePoint                 | {}              |
      | newParentNodeAggregateId            | "folder-opaque" |
      | newSucceedingSiblingNodeAggregateId | null            |
    And the command MoveNodeAggregate is executed with payload:
      | Key                                 | Value      |
      | nodeAggregateId                     | "mover"    |
      | dimensionSpacePoint                 | {}         |
      | newParentNodeAggregateId            | "folder-b" |
      | newSucceedingSiblingNodeAggregateId | null       |
    And I am on URL "/"
    Then the node "mover" in dimension "{}" should resolve to URL "/mover"
    When I am on URL "/mover"
    Then the matched node should be "mover" in dimension "{}"
    When I am on URL "/visible-folder/mover"
    Then No node should match URL "/visible-folder/mover"
