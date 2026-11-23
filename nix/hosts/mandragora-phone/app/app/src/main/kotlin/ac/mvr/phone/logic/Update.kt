package ac.mvr.phone.logic

fun newBuild(published: Long, installed: Long, checked: Long): Boolean = published > installed && published != checked
