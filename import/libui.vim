vim9script

# A view builds a visual representation of a portion of some data model. Such
# visual representation is essentially a list of text lines with properties:
# this is what the Body() method is supposed to return. Each item in the list
# must be a Dictionary with two keys:
#
# - text:  a line of text to be displayed;
# - props: a list of text properties, formatted as in :help text-prop-intro.
#
# Note that a view does not know where to draw itself: such responsibility is
# left to the view's container.
#
# A concrete view is typically, but not mandatorily, also an observer of some
# data model property.
export interface View
  def Body(): list<dict<any>>
endinterface

# A container represents the actual (popup) window in which the views are
# drawn. A container must have a (fixed) width, but the height is dynamic and
# depends on the content of the views that are drawn in the container.
export interface Container
  def WinId(): number
  def Width(): number
  def Redraw()
endinterface
